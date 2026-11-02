import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Everything the minutes writer needs, copied out of SwiftData.
struct MinutesInput: Sendable {
    struct Line: Sendable {
        let time: Double
        let speaker: String
        let text: String
    }

    var kind: MeetingKind = .board
    let title: String
    let date: Date
    let duration: Double
    let attendees: [(name: String, role: String)]
    let lines: [Line]
    let motionMarks: [Double]

    /// Who was there: the members picked at the start, or failing that everyone who spoke.
    var people: [String] {
        if !attendees.isEmpty { return attendees.map { $0.role.isEmpty ? $0.name : "\($0.name) (\($0.role))" } }
        var seen: Set<String> = []
        return lines.map(\.speaker).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// How far a draft has got, for the working readout: the step on screen, which of how many it is, how far along the
/// whole draft is, and where this step ends (the readout creeps toward it, since the model reports nothing while it
/// writes).
struct DraftProgress: Sendable, Equatable {
    let label: String
    let step: Int
    let stepCount: Int
    let fraction: Double
    let ceiling: Double

    /// Reading part `index` (0-based) of `parts`, then writing. Reading shares 5–55%; writing takes the rest.
    static func reading(part index: Int, of parts: Int) -> DraftProgress {
        let share = 0.5 / Double(max(parts, 1))
        let start = 0.05 + share * Double(index)
        return DraftProgress(label: "Reading part \(index + 1) of \(parts)", step: index + 1, stepCount: parts + 1,
                             fraction: start, ceiling: start + share)
    }

    static func writing(_ kind: MeetingKind, afterParts parts: Int) -> DraftProgress {
        DraftProgress(label: kind == .board ? "Writing the minutes" : "Writing the summary", step: parts + 1,
                      stepCount: parts + 1, fraction: 0.55, ceiling: 0.97)
    }
}

/// Drafts minutes (board meetings) or a summary (ad-hoc meetings) on-device. Uses Apple Intelligence
/// (Foundation Models, iOS 26 / macOS 26) when the device supports it; otherwise builds an outline
/// from the transcript for you to finish.
enum MinutesWriter {
    static var aiAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static var aiUnavailableReason: String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return ""
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings to have this written for you."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading. Try again in a little while."
            case .unavailable:
                return "This device doesn't support Apple Intelligence, so you'll get an outline built from the transcript."
            }
        }
        #endif
        return "Automatic writing needs iOS 26 or macOS 26 with Apple Intelligence, so you'll get an outline built from the transcript."
    }

    static func draft(_ input: MinutesInput, progress: @escaping @Sendable (DraftProgress) -> Void) async throws -> String {
        #if canImport(FoundationModels)
        // With no speech there is nothing for the model to read; the outline says so plainly.
        if #available(iOS 26.0, macOS 26.0, *), aiAvailable, !input.lines.isEmpty {
            return try await draftWithAppleIntelligence(input, progress: progress)
        }
        #endif
        return outline(input)
    }

    // MARK: Apple Intelligence

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func draftWithAppleIntelligence(
        _ input: MinutesInput, progress: @escaping @Sendable (DraftProgress) -> Void
    ) async throws -> String {
        // The on-device model has a small context window, so read the meeting in pieces,
        // take notes on each, then write the minutes from the notes.
        let chunks = chunk(input.lines, maxCharacters: 6_000)
        var notes: [String] = []
        for (index, piece) in chunks.enumerated() {
            progress(.reading(part: index, of: chunks.count))
            let session = LanguageModelSession(instructions: Prompts.notes(for: input.kind))
            let text = piece.map { "[\($0.time.clock)] \($0.speaker): \($0.text)" }.joined(separator: "\n")
            let marks = input.motionMarks
                .filter { mark in piece.contains { abs($0.time - mark) < 120 } }
                .map(\.clock)
            let hint = marks.isEmpty ? "" : "\n" + Prompts.markHint(for: input.kind, at: marks)
            let response = try await session.respond(to: text + hint)
            notes.append(response.content)
        }

        progress(.writing(input.kind, afterParts: chunks.count))
        let session = LanguageModelSession(instructions: Prompts.document(for: input.kind))
        let prompt = """
            Meeting: \(input.title)
            Date: \(input.date.formatted(date: .long, time: .shortened))
            Length: \(input.duration.clock)
            Present: \(input.people.isEmpty ? "[CHECK]" : input.people.joined(separator: ", "))

            Notes:
            \(notes.enumerated().map { "Part \($0.offset + 1):\n\($0.element)" }.joined(separator: "\n\n"))
            """
        let response = try await session.respond(to: prompt)
        return response.content
    }
    #endif

    /// Instructions for the on-device model, by meeting kind.
    enum Prompts {
        static func notes(for kind: MeetingKind) -> String {
            switch kind {
            case .board:
                return """
                    You take notes for a board secretary. From this part of a meeting transcript, list only:
                    - agenda topics discussed, with the main points made and who made them (one line each)
                    - motions: exact wording if possible, who moved, who seconded, the vote result and any abstentions
                    - decisions made
                    - action items: who, what, and by when if stated
                    Use the speaker names exactly as written. Mark [TIME] with the timestamp shown. \
                    Do not invent anything that is not in the transcript. If a part has no business, \
                    write one line saying what was talked about.
                    """
            case .adHoc:
                return """
                    You take notes on part of an informal meeting transcript. List:
                    - topics discussed: one line each, with the main points and who made them
                    - decisions or agreements
                    - action items: who will do what, and by when if stated
                    - open questions or things left unresolved
                    Use the speaker names exactly as written. Do not invent anything that is not in the transcript. \
                    Even a casual conversation has topics: always list what was talked about.
                    """
            }
        }

        static func markHint(for kind: MeetingKind, at marks: [String]) -> String {
            switch kind {
            case .board: return "The secretary marked a motion near: \(marks.joined(separator: ", "))."
            case .adHoc: return "The note-taker marked an important moment near: \(marks.joined(separator: ", "))."
            }
        }

        static func document(for kind: MeetingKind) -> String {
            switch kind {
            case .board:
                return """
                    You write formal minutes for a nonprofit or HOA board meeting from a secretary's notes.
                    Write in third person and past tense, concise and neutral. Record actions taken, not every comment.
                    Use these sections in order, as plain text headings: Call to Order, Attendance, Approval of Prior Minutes \
                    (only if discussed), Reports, Old Business, New Business, Motions, Action Items, Adjournment.
                    Under Reports, Old Business and New Business, sum up each topic discussed in a sentence or two.
                    For each motion give: the motion, moved by, seconded by, and the result (for example "Passed 4–0–1, R. James abstaining").
                    Leave a [CHECK] marker anywhere the notes are unclear. Never invent names, numbers, or votes.
                    """
            case .adHoc:
                return """
                    You write a short, useful summary of a meeting from a note-taker's notes, for people who were there \
                    and people who missed it. Plain and friendly, past tense.
                    Use these sections in order, as plain text headings:
                    Summary: two to four sentences on what the meeting was about and where things landed.
                    Topics Discussed: one bullet per topic with its key points.
                    Decisions: one bullet each.
                    Action Items: one bullet each, as "Who: what (by when)", leaving out "by when" if none was stated.
                    Open Questions: one bullet each.
                    Write "None." under a section with nothing in it. Names like "Guest 1" are people the app couldn't \
                    identify; keep them as written. Leave a [CHECK] marker where the notes are unclear. \
                    Never invent names, numbers, dates, or decisions.
                    """
            }
        }
    }

    static func chunk(_ lines: [MinutesInput.Line], maxCharacters: Int) -> [[MinutesInput.Line]] {
        var chunks: [[MinutesInput.Line]] = [[]]
        var size = 0
        for line in lines {
            let length = line.text.count + line.speaker.count + 12
            if size + length > maxCharacters, !(chunks.last?.isEmpty ?? true) {
                chunks.append([])
                size = 0
            }
            chunks[chunks.count - 1].append(line)
            size += length
        }
        return chunks
    }

    // MARK: Outline fallback

    /// What to write when Apple Intelligence can't: an outline built from the transcript.
    static func outline(_ input: MinutesInput) -> String {
        switch input.kind {
        case .board: return boardOutline(input)
        case .adHoc: return summaryOutline(input)
        }
    }

    /// A fill-in-the-blanks draft with every marked motion quoted from the transcript.
    static func boardOutline(_ input: MinutesInput) -> String {
        let start = input.date
        let end = start.addingTimeInterval(input.duration)
        var text = """
            MINUTES — \(input.title.uppercased())
            \(start.formatted(date: .long, time: .omitted))

            CALL TO ORDER
            The meeting was called to order at \(start.formatted(date: .omitted, time: .shortened)) by [Chair].

            ATTENDANCE
            Present: \(input.people.isEmpty ? "[names]" : input.people.joined(separator: ", "))
            Absent: [names]

            """
        if input.lines.isEmpty { text += noSpeech + "\n\n" }

        text += "MOTIONS\n"
        if input.motionMarks.isEmpty {
            text += "[No motions were marked during the meeting. Search the transcript for \"move\" and \"second\".]\n"
        }
        for (number, mark) in input.motionMarks.enumerated() {
            text += "\n\(number + 1). Motion at \(mark.clock): [motion wording]\n"
            text += "   Moved by: [name]   Seconded by: [name]   Result: [passed/failed, vote count]\n"
            text += "   From the transcript:\n"
            for line in lines(near: mark, in: input) {
                text += "   • \(line.speaker): \(line.text)\n"
            }
        }

        text += "\nACTION ITEMS\n"
        let actions = candidates(in: input.lines, cues: actionCues)
        text += actions.isEmpty ? "• [Who] — [what] — [by when]\n" : "Possible action items from the transcript:\n" + bullets(actions)

        text += """

            ADJOURNMENT
            The meeting was adjourned at \(end.formatted(date: .omitted, time: .shortened)).

            Respectfully submitted,
            [Your name], acting secretary
            """
        return text
    }

    /// The likely decisions and to-dos pulled out of the transcript, then the transcript itself.
    static func summaryOutline(_ input: MinutesInput) -> String {
        var text = """
            SUMMARY — \(input.title.uppercased())
            \(input.date.formatted(date: .long, time: .shortened)) · \(input.duration.clock)
            People: \(input.people.isEmpty ? "[names]" : input.people.joined(separator: ", "))

            """
        guard !input.lines.isEmpty else { return text + "\n" + noSpeech + "\n" }

        text += "\nSUMMARY\n[What the meeting was about and where things landed.]\n"
        if !input.motionMarks.isEmpty {
            text += "\nMARKED MOMENTS\n"
            for (number, mark) in input.motionMarks.enumerated() {
                text += "\(number + 1). At \(mark.clock):\n"
                for line in lines(near: mark, in: input) { text += "   • \(line.speaker): \(line.text)\n" }
            }
        }
        let decisions = candidates(in: input.lines, cues: decisionCues)
        text += "\nPOSSIBLE DECISIONS\n" + (decisions.isEmpty ? "None found. [Add any decisions.]\n" : bullets(decisions))
        let actions = candidates(in: input.lines, cues: actionCues)
        text += "\nPOSSIBLE ACTION ITEMS\n" + (actions.isEmpty ? "None found. [Who: what (by when)]\n" : bullets(actions))

        text += "\nTRANSCRIPT\n"
        for line in input.lines { text += "[\(line.time.clock)] \(line.speaker): \(line.text)\n" }
        return text
    }

    static let noSpeech = "[No speech was transcribed. Check the recording plays back and has people talking in it.]"

    /// Phrases that usually mean someone took something on.
    static let actionCues = [
        "i'll", "i will", "we'll", "we will", "can you", "could you", "will you", "need to", "needs to",
        "follow up", "action item", "take care of", "by tomorrow", "next week", "by the end of",
    ]
    /// Phrases that usually mean the group settled something.
    static let decisionCues = [
        "agreed", "we agree", "decided", "let's go with", "go ahead with", "settled", "approved",
        "motion passes", "motion carries", "sounds good", "that works",
    ]
    /// At most this many possible decisions or action items, so the outline stays readable.
    static let maxCandidates = 12

    /// Lines containing any cue as whole words, in order.
    static func candidates(in lines: [MinutesInput.Line], cues: [String]) -> [MinutesInput.Line] {
        let padded = cues.map { " \(normalized($0)) " }
        return Array(lines.filter { line in
            let text = " \(normalized(line.text)) "
            return padded.contains { text.contains($0) }
        }.prefix(maxCandidates))
    }

    /// Lowercase words separated by single spaces, apostrophes kept ("I’ll," → "i'll").
    private static func normalized(_ text: String) -> String {
        let plain = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        let spaced = String(plain.map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " })
        return spaced.split(separator: " ").joined(separator: " ")
    }

    private static func lines(near mark: Double, in input: MinutesInput) -> [MinutesInput.Line] {
        Array(input.lines.filter { $0.time >= mark - 30 && $0.time <= mark + 90 }.prefix(6))
    }

    private static func bullets(_ lines: [MinutesInput.Line]) -> String {
        lines.map { "• [\($0.time.clock)] \($0.speaker): \($0.text)\n" }.joined()
    }
}
