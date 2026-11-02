import AVFoundation
import Foundation
import Observation

/// Where sound plays on iPhone: the phone itself, or another device such as a car's Bluetooth, headphones or an
/// AirPlay speaker. iOS sends playback to the last device that connected, so a phone still paired with a car plays
/// into the car's stereo even when you're standing outside it. Review and the Transcript tab say so and offer a key
/// to change it.
///
/// On the Mac, sound goes wherever the system's output is set (the menu bar's Sound menu), so `deviceName` stays nil.
@Observable
final class AudioRoute: @unchecked Sendable {
    /// The phone's own route, kept current as devices come and go.
    static let shared = AudioRoute(observingSystem: ())

    /// The device sound plays on when it isn't this iPhone, else nil.
    private(set) var deviceName: String?

    /// A fixed route, for previews and the screenshot tests.
    init(deviceName: String?) {
        self.deviceName = deviceName
    }

    private init(observingSystem: Void) {
        #if os(iOS)
        refresh()
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        #endif
    }

    /// Reads the route again. Call it on the main thread; the players call it after switching the session to
    /// playback, which can change where sound goes.
    func refresh() {
        #if os(iOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map {
            Output(name: $0.portName, isPhone: Self.phonePorts.contains($0.portType))
        }
        let name = Self.deviceName(of: outputs)
        if name != deviceName { deviceName = name }
        #endif
    }

    /// Re-reads the shared route on the main thread, from wherever the session was just changed.
    static func refreshShared() {
        DispatchQueue.main.async { shared.refresh() }
    }

    // MARK: Which device

    /// One of the route's outputs.
    struct Output: Equatable {
        let name: String
        /// The phone's own speaker or earpiece.
        let isPhone: Bool
    }

    #if os(iOS)
    private static let phonePorts: Set<AVAudioSession.Port> = [.builtInSpeaker, .builtInReceiver]
    #endif

    /// The first output that isn't the phone itself, by name; nil when sound plays on the phone or nothing is
    /// connected.
    static func deviceName(of outputs: [Output]) -> String? {
        for output in outputs where !output.isPhone {
            let name = output.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "another device" : name
        }
        return nil
    }

    /// What Review and the Transcript tab say while sound goes elsewhere.
    static func note(deviceName: String) -> String {
        "Sound is playing on \(deviceName). Use the AirPlay key to play it on this iPhone."
    }
}
