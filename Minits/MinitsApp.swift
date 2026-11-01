import SwiftData
import SwiftUI

@main
struct MinitsApp: App {
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $router.path) {
                HomeView()
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .rollCall: RollCallView()
                        case .recording(let meeting): RecordingView(meeting: meeting)
                        case .meeting(let meeting): MeetingView(meeting: meeting)
                        }
                    }
            }
            .environment(router)
            .tint(Color.sk1Ink)
            // A recording the app didn't get to finish can't be resumed, so take its lock-screen REC away.
            .task { RecordingLiveActivity.endLeftovers() }
            #if os(macOS)
            .frame(minWidth: 420, idealWidth: 480, minHeight: 640, idealHeight: 820)
            #endif
        }
        .modelContainer(for: [Member.self, Meeting.self, TranscriptLine.self])
        #if os(macOS)
        .defaultSize(width: 480, height: 820)
        #endif
    }
}

enum Route: Hashable {
    case rollCall
    case recording(Meeting)
    case meeting(Meeting)
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []

    /// After a meeting ends, swap the recording screen for the meeting screen
    /// so Back goes home instead of to a finished recording.
    func showMeeting(_ meeting: Meeting) {
        path = [.meeting(meeting)]
    }
}
