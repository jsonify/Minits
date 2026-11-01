import Foundation
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

/// Starts, updates and ends the recording's Live Activity on iPhone (lock screen and Dynamic Island). Does nothing on
/// Mac, or when Live Activities are turned off for Minits in Settings.
@MainActor
final class RecordingLiveActivity {
    #if os(iOS) && canImport(ActivityKit)
    private var activity: Activity<RecordingActivityAttributes>?
    private var last: RecordingActivityAttributes.ContentState?
    #endif

    init() {}

    func start(title: String, kindName: String, markName: String, present: Int, marks: Int) {
        #if os(iOS) && canImport(ActivityKit)
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingActivityAttributes(title: title, kindName: kindName, markName: markName,
                                                     present: present)
        let state = RecordingActivityAttributes.ContentState(isPaused: false, wasInterrupted: false,
                                                             timerStart: Date(), elapsed: 0, marks: marks)
        activity = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
        last = state
        #endif
    }

    /// Sends the recording's state, if it changed.
    func update(isPaused: Bool, wasInterrupted: Bool, elapsed: TimeInterval, marks: Int) {
        #if os(iOS) && canImport(ActivityKit)
        guard let activity else { return }
        let state = RecordingActivityAttributes.ContentState(
            isPaused: isPaused, wasInterrupted: wasInterrupted,
            timerStart: Date().addingTimeInterval(-elapsed), elapsed: elapsed, marks: marks)
        if let last, last.isPaused == state.isPaused, last.wasInterrupted == state.wasInterrupted,
           last.marks == state.marks, abs(last.timerStart.timeIntervalSince(state.timerStart)) < 2 {
            return
        }
        last = state
        Task { await activity.update(.init(state: state, staleDate: nil)) }
        #endif
    }

    /// Takes it off the lock screen and the Dynamic Island.
    func end() {
        #if os(iOS) && canImport(ActivityKit)
        guard let activity else { return }
        self.activity = nil
        last = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        #endif
    }

    /// Ends any left over from a recording the app didn't get to finish (it was closed or crashed), so a stale REC
    /// doesn't stay on the lock screen. Call at launch.
    static func endLeftovers() {
        #if os(iOS) && canImport(ActivityKit)
        for activity in Activity<RecordingActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }
}
