import AVFoundation
import Foundation
import Observation

/// Plays one stretch of a meeting recording, so you can hear a line before fixing its speaker.
///
/// The player and the audio session live on a background queue (`PlayerIO`), like the recorder's: switching the
/// session to playback and starting a player while it's active can block the main thread for a moment.
@MainActor
@Observable
final class ClipPlayer {
    private(set) var playingLineID: UUID?
    private let io = PlayerIO()
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    func toggle(lineID: UUID, url: URL, from start: Double, to end: Double) {
        if playingLineID == lineID {
            stop()
            return
        }
        stop()
        // A little lead-in helps you recognize the voice.
        let from = max(0, start - 0.3)
        playingLineID = lineID
        io.play(url: url, from: from) { [self] in
            // The file couldn't be opened: put the key back.
            Task { @MainActor in
                if playingLineID == lineID { stop() }
            }
        }
        let length = max(0.5, end - from + 0.3)
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(length))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        if playingLineID != nil { io.stop() }
        playingLineID = nil
    }
}

/// The `AVAudioPlayer` and the audio session, used only on one serial background queue. Calls return at once and
/// run in the order they're made.
private final class PlayerIO: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jsonify.minits.player", qos: .userInitiated)
    /// Only touched on `queue`.
    private var player: AVAudioPlayer?

    /// Plays `url` from `from` seconds; calls `failed` (on the queue) if it can't be opened.
    func play(url: URL, from: TimeInterval, failed: @escaping @Sendable () -> Void) {
        queue.async {
            self.player?.stop()
            #if os(iOS)
            // Set every time: recording switches the session to .record.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio)
            try? session.setActive(true)
            #endif
            guard let player = try? AVAudioPlayer(contentsOf: url) else {
                self.player = nil
                failed()
                return
            }
            player.currentTime = from
            player.play()
            self.player = player
        }
    }

    func stop() {
        queue.async {
            self.player?.stop()
            self.player = nil
        }
    }
}
