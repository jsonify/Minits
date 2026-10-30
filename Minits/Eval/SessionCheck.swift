import Foundation

/// What a session folder holds, gathered by `minits-eval check` (durations need AVFoundation, so the
/// CLI reads the files and this type stays plain for tests).
struct SessionInventory: Equatable, Sendable {
    var config = SessionConfig()
    /// Length of table.wav, or nil when there is none.
    var tableSeconds: Double?
    /// Length of each enroll/<member>.wav.
    var enrollSeconds: [String: Double] = [:]
    /// Length of each tracks/<member>.wav.
    var trackSeconds: [String: Double] = [:]
    /// Offset the clap proposes for each track; missing when no clap was found.
    var clapOffsets: [String: Double] = [:]
    /// Audio the harness can't read yet (an .m4a from Voice Memos), relative to the session folder.
    var unconvertedAudio: [String] = []
}

/// One thing `check` found, worded for the person who just copied the files over.
struct SessionFinding: Equatable, Sendable {
    enum Severity: String, Sendable { case problem, warning }
    var severity: Severity
    var message: String
}

/// Catches the mistakes that are cheap to fix the day of the recording and expensive afterwards:
/// a name spelled two ways, a missing track, a sample too short for the app to accept.
enum SessionCheck {
    /// The app refuses enrollment samples shorter than this and stops recording at `enrollMaxSeconds`.
    static let enrollMinSeconds = 4.0
    static let enrollMaxSeconds = 15.0
    /// The pub and quiet-room sessions are meant to be 15-20 minutes of discussion.
    static let tableMinSeconds = 15.0 * 60
    /// A personal track much shorter than the table recording missed part of the meeting.
    static let trackMinShare = 0.9

    static let audioExtensions: Set<String> = ["m4a", "mp3", "aac", "caf", "aif", "aiff", "mp4", "mov", "flac"]

    static func findings(for inventory: SessionInventory) -> [SessionFinding] {
        var result: [SessionFinding] = []
        func problem(_ message: String) { result.append(SessionFinding(severity: .problem, message: message)) }
        func warning(_ message: String) { result.append(SessionFinding(severity: .warning, message: message)) }

        for file in inventory.unconvertedAudio.sorted() {
            let wav = (file as NSString).deletingPathExtension + ".wav"
            problem("\(file) isn't a WAV. Convert it: afconvert -f WAVE -d LEI16@16000 -c 1 \"\(file)\" \"\(wav)\"")
        }

        guard let table = inventory.tableSeconds else {
            problem("No table.wav (the shared phone's recording).")
            return result
        }
        if table < tableMinSeconds {
            warning("table.wav is \(clock(table)); the eval sessions should be at least \(clock(tableMinSeconds)).")
        }

        let enrolled = Set(inventory.enrollSeconds.keys)
        let tracked = Set(inventory.trackSeconds.keys)
        var members = inventory.config.members
        if members.isEmpty {
            warning("session.json lists no members; checking against the enroll/ and tracks/ file names instead.")
            members = enrolled.union(tracked).sorted()
        }
        let listed = Set(members)

        for member in members {
            if !enrolled.contains(member) { problem("No enroll/\(member).wav.") }
            if !tracked.contains(member) { problem("No tracks/\(member).wav, so \(member)'s lines can't be labeled.") }
        }
        for name in enrolled.subtracting(listed).sorted() {
            problem("enroll/\(name).wav doesn't match a member in session.json (\(members.joined(separator: ", "))).")
        }
        for name in tracked.subtracting(listed).sorted() {
            problem("tracks/\(name).wav doesn't match a member in session.json (\(members.joined(separator: ", "))).")
        }

        for (member, seconds) in inventory.enrollSeconds.sorted(by: { $0.key < $1.key }) {
            if seconds < enrollMinSeconds {
                problem("enroll/\(member).wav is \(String(format: "%.1f", seconds)) s; the app needs at least \(Int(enrollMinSeconds)) s (aim for 10).")
            } else if seconds > enrollMaxSeconds {
                warning("enroll/\(member).wav is \(String(format: "%.1f", seconds)) s; the app stops at \(Int(enrollMaxSeconds)) s, so this sample is longer than any real one.")
            }
        }

        for (member, seconds) in inventory.trackSeconds.sorted(by: { $0.key < $1.key }) {
            if seconds < table * trackMinShare {
                warning("tracks/\(member).wav is \(clock(seconds)) but table.wav is \(clock(table)); lines outside the track won't be labeled.")
            }
            if inventory.clapOffsets[member] == nil && inventory.config.trackOffsetsSeconds[member] == nil {
                warning("No clap found in tracks/\(member).wav and no offset in session.json; labels will assume it started with table.wav.")
            }
        }
        return result
    }

    static func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
