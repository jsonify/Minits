import Foundation
import SwiftData

/// A board member (or regular guest) whose voice the app has learned.
@Model
final class Member {
    var id: UUID = UUID()
    var name: String = ""
    var role: String = ""
    /// WeSpeaker voiceprint from FluidAudio, stored as raw Float bytes.
    var voiceprint: Data?
    var voiceSavedAt: Date?
    var sortOrder: Int = 0
    /// Which avatar colour the member has, kept so removing someone doesn't recolour everyone after them.
    /// nil for members saved before colours were stored, until `Member.fillInColors` gives them the one they had.
    var colorIndex: Int?

    init(name: String, role: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.role = role
        self.sortOrder = sortOrder
    }

    var hasVoice: Bool { voiceprint != nil }

    var embedding: [Float]? {
        get { voiceprint.map(Data.toFloats) }
        set { voiceprint = newValue.map(Data.fromFloats) }
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

extension Member {
    /// How many avatar colours there are.
    static let colorCount = 7

    /// The first colour no one has, or else the one fewest have.
    static func nextColor(among members: [Member]) -> Int {
        let used = members.compactMap(\.colorIndex).map { $0 % colorCount }
        return (0..<colorCount).min { a, b in
            used.filter { $0 == a }.count < used.filter { $0 == b }.count
        } ?? 0
    }

    /// Gives members saved before colours were stored the colour their place in the list gave them, so nothing
    /// changes on screen. `members` in list order. Returns whether any changed.
    @discardableResult
    static func fillInColors(_ members: [Member]) -> Bool {
        var changed = false
        for (index, member) in members.enumerated() where member.colorIndex == nil {
            member.colorIndex = index % colorCount
            changed = true
        }
        return changed
    }

    /// Changes the name and role. The voiceprint stays. With `updatingTranscripts`, every line already attributed to
    /// this member takes the new name too; written minutes and summaries keep the old one until they're redrafted.
    func update(name: String, role: String, updatingTranscripts: Bool, in context: ModelContext) {
        if updatingTranscripts, name != self.name {
            let speaker: UUID? = id
            let lines = (try? context.fetch(FetchDescriptor<TranscriptLine>(
                predicate: #Predicate { $0.speakerID == speaker }))) ?? []
            for line in lines { line.speakerName = name }
        }
        self.name = name
        self.role = role
        try? context.save()
    }
}

enum MeetingStatus: String, Codable {
    case recording, processing, needsReview, ready, failed
}

/// What the meeting is, which decides what gets written afterwards.
enum MeetingKind: String, Codable, CaseIterable, Identifiable {
    /// Formal minutes: attendance, motions, votes, action items.
    case board
    /// A plain summary: what was discussed, decisions, action items.
    case adHoc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .board: return "Board meeting"
        case .adHoc: return "Ad-hoc meeting"
        }
    }

    /// What the written-up result is called on screen.
    var documentName: String {
        switch self {
        case .board: return "Minutes"
        case .adHoc: return "Summary"
        }
    }

    /// What tapping the mark button records during the meeting.
    var markName: String {
        switch self {
        case .board: return "motion"
        case .adHoc: return "moment"
        }
    }
}

@Model
final class Meeting {
    var id: UUID = UUID()
    var title: String = ""
    var startedAt: Date = Date()
    var durationSeconds: Double = 0
    /// File name inside the app's Recordings folder.
    var audioFileName: String = ""
    var statusRaw: String = MeetingStatus.recording.rawValue
    var errorMessage: String?
    /// Meetings recorded before ad-hoc meetings existed decode as board meetings.
    var kindRaw: String = MeetingKind.board.rawValue
    /// Seconds into the recording where "Mark motion" (or "Mark moment") was tapped.
    var motionMarks: [Double] = []
    /// Members who were present (had their voice on file when the meeting started).
    var attendeeIDs: [UUID] = []
    var minutes: String?
    @Relationship(deleteRule: .cascade, inverse: \TranscriptLine.meeting)
    var lines: [TranscriptLine] = []

    init(title: String, kind: MeetingKind = .board, attendeeIDs: [UUID]) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.startedAt = Date()
        self.attendeeIDs = attendeeIDs
        self.audioFileName = "\(id.uuidString).wav"
    }

    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var kind: MeetingKind {
        get { MeetingKind(rawValue: kindRaw) ?? .board }
        set { kindRaw = newValue.rawValue }
    }

    var audioURL: URL { Storage.recordingsFolder.appendingPathComponent(audioFileName) }

    var sortedLines: [TranscriptLine] { lines.sorted { $0.start < $1.start } }

    /// Deletes the meeting with its transcript and its recording.
    func delete(from context: ModelContext) {
        try? FileManager.default.removeItem(at: audioURL)
        context.delete(self)
        try? context.save()
    }
    var linesNeedingReview: [TranscriptLine] { sortedLines.filter { $0.needsReview } }
}

@Model
final class TranscriptLine {
    var id: UUID = UUID()
    var start: Double = 0
    var end: Double = 0
    var text: String = ""
    /// Matched member, or nil for someone the app couldn't identify.
    var speakerID: UUID?
    /// Name shown in the transcript ("Maria Lopez", "Guest 1"…).
    var speakerName: String = ""
    /// The runner-up guess, offered on the review screen.
    var alternateSpeakerID: UUID?
    /// 0–1, how sure the voice match was.
    var confidence: Double = 0
    var needsReview: Bool = false
    var reviewNote: String?
    var meeting: Meeting?

    init(start: Double, end: Double, text: String) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.text = text
    }
}

// MARK: - Helpers

extension Data {
    static func fromFloats(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func toFloats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
    }
}

enum Storage {
    static var recordingsFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func temporaryRecordingURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sample-\(UUID().uuidString).wav")
    }
}

extension TimeInterval {
    /// 0:42, 41:02 or 1:03:12
    var clock: String {
        let total = Int(self.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// 00:42:15, for the big recording timer
    var longClock: String {
        let total = Int(self.rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
