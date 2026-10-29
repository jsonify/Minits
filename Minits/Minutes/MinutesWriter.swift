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

    let title: String
    let date: Date
    let duration: Double
    let attendees: [(name: String, role: String)]
    let lines: [Line]
    let motionMarks: [Double]
}

/// Drafts minutes on-device. Uses Apple Intelligence (Foundation Models, iOS 26 / macOS 26)
/// when the device supports it; otherwise builds a structured outline you fill in.
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
                return "Turn on Apple Intelligence in Settings to have the minutes written for you."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading. Try again in a little while."
            case .unavailable:
                return "This device doesn't support Apple Intelligence, so you'll get an outline to fill in."
            }
        }
        #endif
        return "Automatic writing needs iOS 26 or macOS 26 with Apple Intelligence, so you'll get an outline to fill in."
    }

    static func draft(_ input: MinutesInput, progress: @escaping @Sendable (String) -> Void) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), aiAvailable {
            return try await draftWithAppleIntelligence(input, progress: progress)
        }
        #endif
        return outline(input, notes: nil)
    }

    // MARK: Apple Intelligence

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func draftWithAppleIntelligence(
        _ input: MinutesInput, progress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        // The on-device model has a small context window, so read the meeting in pieces,
        // take notes on each, then write the minutes from the notes.
        let chunks = chunk(input.lines, maxCharacters: 6_000)
        var notes: [String] = []
        for (index, piece) in chunks.enumerated() {
            progress("Reading part \(index + 1) of \(chunks.count)")
            let session = LanguageModelSession(instructions: """
                You take notes for a board secretary. From this part of a meeting transcript, list only:
                - agenda topics discussed (one line each)
                - motions: exact wording if possible, who moved, who seconded, the vote result and any abstentions
                - decisions made
                - action items: who, what, and by when if stated
                Use the speaker names exactly as written. Mark [TIME] with the timestamp shown. \
                Do not invent anything that is not in the transcript. If a part has none of these, write "No business."
                """)
            let text = piece.map { "[\($0.time.clock)] \($0.speaker): \($0.text)" }.joined(separator: "\n")
            let marks = input.motionMarks
                .filter { mark in piece.contains { abs($0.time - mark) < 120 } }
                .map(\.clock)
            let hint = marks.isEmpty ? "" : "\nThe secretary marked a motion near: \(marks.joined(separator: ", "))."
            let response = try await session.respond(to: text + hint)
            notes.append(response.content)
        }

        progress("Writing the minutes")
        let session = LanguageModelSession(instructions: """
            You write formal minutes for a nonprofit or HOA board meeting from a secretary's notes.
            Write in third person and past tense, concise and neutral. Record actions taken, not every comment.
            Use these sections in order, as plain text headings: Call to Order, Attendance, Approval of Prior Minutes \
            (only if discussed), Reports, Old Business, New Business, Motions, Action Items, Adjournment.
            For each motion give: the motion, moved by, seconded by, and the result (for example "Passed 4–0–1, R. James abstaining").
            Leave a [CHECK] marker anywhere the notes are unclear. Never invent names, numbers, or votes.
            """)
        let attendance = input.attendees.map { $0.role.isEmpty ? $0.name : "\($0.name) (\($0.role))" }
            .joined(separator: ", ")
        let prompt = """
            Meeting: \(input.title)
            Date: \(input.date.formatted(date: .long, time: .shortened))
            Length: \(input.duration.clock)
            Present: \(attendance.isEmpty ? "[CHECK]" : attendance)

            Notes:
            \(notes.enumerated().map { "Part \($0.offset + 1):\n\($0.element)" }.joined(separator: "\n\n"))
            """
        let response = try await session.respond(to: prompt)
        return response.content
    }
    #endif

    private static func chunk(_ lines: [MinutesInput.Line], maxCharacters: Int) -> [[MinutesInput.Line]] {
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

    /// A fill-in-the-blanks draft with every marked motion quoted from the transcript.
    static func outline(_ input: MinutesInput, notes: String?) -> String {
        let start = input.date
        let end = start.addingTimeInterval(input.duration)
        let attendance = input.attendees.map { $0.role.isEmpty ? $0.name : "\($0.name) (\($0.role))" }
        var text = """
            MINUTES — \(input.title.uppercased())
            \(start.formatted(date: .long, time: .omitted))

            CALL TO ORDER
            The meeting was called to order at \(start.formatted(date: .omitted, time: .shortened)) by [Chair].

            ATTENDANCE
            Present: \(attendance.isEmpty ? "[names]" : attendance.joined(separator: ", "))
            Absent: [names]

            """

        text += "MOTIONS\n"
        if input.motionMarks.isEmpty {
            text += "[No motions were marked during the meeting. Search the transcript for \"move\" and \"second\".]\n"
        }
        for (number, mark) in input.motionMarks.enumerated() {
            let nearby = input.lines.filter { $0.time >= mark - 30 && $0.time <= mark + 90 }
            text += "\n\(number + 1). Motion at \(mark.clock): [motion wording]\n"
            text += "   Moved by: [name]   Seconded by: [name]   Result: [passed/failed, vote count]\n"
            text += "   From the transcript:\n"
            for line in nearby.prefix(6) {
                text += "   • \(line.speaker): \(line.text)\n"
            }
        }

        text += """

            ACTION ITEMS
            • [Who] — [what] — [by when]

            ADJOURNMENT
            The meeting was adjourned at \(end.formatted(date: .omitted, time: .shortened)).

            Respectfully submitted,
            [Your name], acting secretary
            """
        return text
    }
}
