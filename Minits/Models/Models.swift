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

enum MeetingStatus: String, Codable {
    case recording, processing, needsReview, ready, failed
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
    /// Seconds into the recording where "Mark motion" was tapped.
    var motionMarks: [Double] = []
    /// Members who were present (had their voice on file when the meeting started).
    var attendeeIDs: [UUID] = []
    var minutes: String?
    @Relationship(deleteRule: .cascade, inverse: \TranscriptLine.meeting)
    var lines: [TranscriptLine] = []

    init(title: String, attendeeIDs: [UUID]) {
        self.id = UUID()
        self.title = title
        self.startedAt = Date()
        self.attendeeIDs = attendeeIDs
        self.audioFileName = "\(id.uuidString).wav"
    }

    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var audioURL: URL { Storage.recordingsFolder.appendingPathComponent(audioFileName) }

    var sortedLines: [TranscriptLine] { lines.sorted { $0.start < $1.start } }
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
