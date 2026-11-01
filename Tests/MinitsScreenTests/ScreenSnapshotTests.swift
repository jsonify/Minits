@testable import Minits
import SwiftData
import SwiftUI
import UIKit
import XCTest

/// Renders every screen and sheet, in each state worth seeing, in light and dark at an iPhone width (390 pt) and a wide
/// window's (720 pt, about the Mac's), from `ScreenFixtures`. The PNGs go to `MINITS_SNAPSHOT_DIR` when it's set
/// (CI uploads them as the `minits-screens` artifact) and are attached to the test results either way.
///
/// It checks that each screen renders; it doesn't compare against saved images. Run it on the iOS Simulator:
/// `xcodebuild test -scheme MinitsScreenTests -destination 'platform=iOS Simulator,name=iPhone 16'`.
final class ScreenSnapshotTests: XCTestCase {
    private struct Screen {
        let name: String
        /// Which kind of meeting "last used" is, for Home and roll call.
        var lastKind: MeetingKind = .board
        var modelsReady = true
        /// A sheet brings its own navigation bar; a pushed screen gets one here.
        var inNavigationStack = true
        let view: (ScreenFixtures) -> AnyView
    }

    private static let widths: [(name: String, width: CGFloat, height: CGFloat)] = [
        ("iphone", 390, 844),
        ("wide", 720, 900),
    ]

    @MainActor
    func testEveryScreen() throws {
        let fixtures = try ScreenFixtures()
        let empty = try ScreenFixtures.emptyContainer()
        let folder = ProcessInfo.processInfo.environment["MINITS_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
        if let folder { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }

        let screens: [Screen] = [
            Screen(name: "01-home-empty", modelsReady: false) { _ in AnyView(HomeView()) },
            Screen(name: "02-home") { _ in AnyView(HomeView()) },
            Screen(name: "03-roll-call") { _ in AnyView(RollCallView()) },
            Screen(name: "04-roll-call-ad-hoc", lastKind: .adHoc) { _ in AnyView(RollCallView()) },
            Screen(name: "05-add-member", inNavigationStack: false) { _ in AnyView(MemberSheet { _, _, _ in }) },
            Screen(name: "06-voice-sample", inNavigationStack: false) { f in
                AnyView(VoiceSampleSheet(member: f.members[3], others: Array(f.members.prefix(3))))
            },
            Screen(name: "07-recording") { f in AnyView(RecordingView(meeting: f.recording)) },
            Screen(name: "08-processing") { f in AnyView(MeetingView(meeting: f.processing)) },
            Screen(name: "09-failed") { f in AnyView(MeetingView(meeting: f.failed)) },
            Screen(name: "10-review") { f in AnyView(MeetingView(meeting: f.review, initialTab: .review)) },
            Screen(name: "11-transcript") { f in AnyView(MeetingView(meeting: f.review, initialTab: .transcript)) },
            Screen(name: "12-summary-to-write") { f in
                AnyView(MeetingView(meeting: f.summaryToWrite, initialTab: .minutes))
            },
            Screen(name: "13-minutes") { f in AnyView(MeetingView(meeting: f.minutes, initialTab: .minutes)) },
            Screen(name: "14-edit-member", inNavigationStack: false) { f in
                AnyView(MemberSheet(member: f.members[1]) { _, _, _ in })
            },
            Screen(name: "15-rename-meeting", inNavigationStack: false) { f in
                AnyView(MeetingTitleSheet(title: f.minutes.title) { _ in })
            },
            Screen(name: "19-intro", inNavigationStack: false) { _ in AnyView(IntroView(mic: .undetermined) {}) },
            Screen(name: "20-intro-mic-off", inNavigationStack: false) { _ in AnyView(IntroView(mic: .denied) {}) },
        ]

        for screen in screens {
            let container = screen.name == "01-home-empty" ? empty : fixtures.container
            UserDefaults.standard.set(screen.modelsReady, forKey: "modelsReady")
            UserDefaults.standard.set(screen.lastKind.rawValue, forKey: "lastMeetingKind")
            // Home would put the first-run intro over itself; the intro has its own screens.
            UserDefaults.standard.set(true, forKey: "hasSeenIntro")
            for size in Self.widths {
                for dark in [false, true] {
                    let name = "\(screen.name)-\(size.name)-\(dark ? "dark" : "light")"
                    let content = screen.view(fixtures)
                    let root = Group {
                        if screen.inNavigationStack {
                            NavigationStack { content }
                        } else {
                            content
                        }
                    }
                    .environment(Router())
                    .environment(\.runsMeetingWork, false)
                    .tint(Color.sk1Ink)
                    .modelContainer(container)

                    let png = try XCTUnwrap(
                        Self.render(root, size: CGSize(width: size.width, height: size.height), dark: dark),
                        "\(name) didn't render")
                    XCTAssertGreaterThan(png.count, 10_000, "\(name) looks blank")

                    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                    attachment.name = name
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    if let folder { try png.write(to: folder.appendingPathComponent("\(name).png")) }
                }
            }
        }
    }

    /// Puts `view` in its own window at `size`, lets SwiftUI lay it out and fetch its data, and draws the window.
    @MainActor
    private static func render<V: View>(_ view: V, size: CGSize, dark: Bool) -> Data? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: .zero)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        // @Query fetches, onAppear picks the tab, and the first frame of each TimelineView draws.
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            if !window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) {
                window.layer.render(in: context.cgContext)
            }
        }
        window.isHidden = true
        window.rootViewController = nil
        return image.pngData()
    }
}
