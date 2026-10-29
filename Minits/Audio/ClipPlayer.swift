import AVFoundation
import Foundation
import Observation

/// Plays one stretch of a meeting recording, so you can hear a line before fixing its speaker.
@MainActor
@Observable
final class ClipPlayer {
    private(set) var playingLineID: UUID?
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func toggle(lineID: UUID, url: URL, from start: Double, to end: Double) {
        if playingLineID == lineID {
            stop()
            return
        }
        stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        // A little lead-in helps you recognize the voice.
        let from = max(0, start - 0.3)
        player.currentTime = from
        player.play()
        self.player = player
        playingLineID = lineID
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
        player?.stop()
        player = nil
        playingLineID = nil
    }
}
