import Foundation

/// What the Live Activity's keys ask the recording screen to do. They're sent as a notification in the app's own
/// process (the intents below run there), and the recording screen listens for it.
enum RecordingCommand: String, Sendable {
    case togglePause
    case mark
}

extension Notification.Name {
    /// Posted with a `RecordingCommand` raw value as its object.
    static let minitsRecordingCommand = Notification.Name("com.jsonify.minits.recording-command")
}

#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import AppIntents

/// The recording's Live Activity (lock screen and Dynamic Island). Compiled into the app, which starts and updates
/// it, and into the MinitsRecordingWidget extension, which draws it.
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isPaused: Bool
        /// Paused by a call or another app, not by a tap.
        var wasInterrupted: Bool
        /// When a running timer would have read 0:00: now minus the elapsed time. The widget counts up from it.
        var timerStart: Date
        /// The elapsed time, shown as it is while paused.
        var elapsed: TimeInterval
        /// How many motions (or moments) have been marked.
        var marks: Int
    }

    var title: String
    /// "BOARD" or "AD-HOC".
    var kindName: String
    /// "Motion" or "Moment".
    var markName: String
    /// How many members are here.
    var present: Int
}

/// The Live Activity's Pause/Resume key. Runs in the app, which is still running because it's recording.
struct ToggleRecordingPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or resume the recording"

    init() {}

    func perform() async throws -> some IntentResult {
        await RecordingCommand.togglePause.send()
        return .result()
    }
}

/// The Live Activity's Mark key: marks a motion (board meeting) or a moment (ad-hoc) at the current time.
struct MarkRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark a motion or moment"

    init() {}

    func perform() async throws -> some IntentResult {
        await RecordingCommand.mark.send()
        return .result()
    }
}

extension RecordingCommand {
    @MainActor
    func send() {
        NotificationCenter.default.post(name: .minitsRecordingCommand, object: rawValue)
    }
}
#endif
