import AVFoundation
import Foundation
import Observation

/// Plays a whole meeting recording for the Transcript tab: play and pause, jump to a time or a line, skip back or
/// forward, and change the speed. It reports where it's got to a few times a second, so the transcript can light the
/// line being spoken.
///
/// The file isn't opened until the first play, so showing the Transcript tab costs nothing. Like `ClipPlayer`, the
/// player and the audio session live on a background queue (`MeetingPlayerIO`), so switching the session to playback
/// never stalls the main thread.
@MainActor
@Observable
final class MeetingPlayer {
    /// Speeds the speed key steps through.
    static let rates: [Float] = [1, 1.5, 2]

    private(set) var isPlaying = false
    /// Where playback is, in seconds from the start of the recording.
    private(set) var currentTime: Double = 0
    /// The recording's length once it's been opened; until then, nil (show the meeting's saved duration instead).
    private(set) var duration: Double?
    private(set) var rate: Float = 1
    /// The recording couldn't be opened (it's missing or unreadable).
    private(set) var failed = false
    /// Whether anything has been played or picked yet, so nothing is lit before then.
    private(set) var hasStarted = false

    private let io = MeetingPlayerIO()
    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var timer: Timer?
    /// Bumped by every command, so a position reading that left before a command doesn't undo it.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var polling = false

    /// The recording to play. Call before anything else; calling again with another file stops the first.
    func load(url: URL) {
        guard url != self.url else { return }
        stop()
        self.url = url
        failed = false
        duration = nil
        currentTime = 0
        hasStarted = false
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    /// Plays from `time` (seconds), or from where it is.
    func play(from time: Double? = nil) {
        guard let url else { return }
        if let time {
            currentTime = clamp(time)
        } else if let duration, currentTime >= duration - 0.5 {
            currentTime = 0   // Finished: play again from the start.
        }
        hasStarted = true
        isPlaying = true
        generation += 1
        let token = generation
        let from = currentTime
        let rate = rate
        Task {
            let status = await io.play(url: url, from: from, rate: rate)
            guard token == generation else { return }
            if let status {
                failed = false
                apply(status)
                startTimer()
            } else {
                failed = true
                isPlaying = false
                stopTimer()
            }
        }
    }

    func pause() {
        isPlaying = false
        stopTimer()
        generation += 1
        let token = generation
        Task {
            let status = await io.pause()
            guard token == generation, let status else { return }
            currentTime = status.time
        }
    }

    /// Moves to `time` (seconds), playing on from there if it was playing.
    func seek(to time: Double) {
        currentTime = clamp(time)
        hasStarted = true
        generation += 1
        let token = generation
        let target = currentTime
        Task {
            let status = await io.seek(to: target)
            guard token == generation, let status else { return }
            apply(status)
        }
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    /// Steps to the next speed in `rates`, back to 1× after the last.
    func cycleRate() {
        let index = Self.rates.firstIndex(of: rate) ?? 0
        rate = Self.rates[(index + 1) % Self.rates.count]
        let rate = rate
        Task { await io.setRate(rate) }
    }

    /// Stops and lets go of the file and the audio session.
    func stop() {
        stopTimer()
        generation += 1
        isPlaying = false
        io.stop()
    }

    private func clamp(_ time: Double) -> Double {
        let end = duration ?? .greatestFiniteMagnitude
        return min(max(time, 0), max(end - 0.1, 0))
    }

    private func apply(_ status: MeetingPlayerIO.Status) {
        duration = status.duration
        currentTime = status.time
        if isPlaying, !status.playing {
            // It reached the end. AVAudioPlayer goes back to 0 there; stay at the end so it reads as finished.
            isPlaying = false
            currentTime = status.duration
            stopTimer()
        }
    }

    // MARK: Position

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() async {
        guard isPlaying, !polling else { return }
        polling = true
        defer { polling = false }
        let token = generation
        guard let status = await io.status(), token == generation, isPlaying else { return }
        apply(status)
    }
}

/// The `AVAudioPlayer` and the audio session, used only on one serial background queue. Each call waits for its
/// work, so calls run in the order they're made.
private final class MeetingPlayerIO: @unchecked Sendable {
    struct Status: Sendable {
        let time: Double
        let duration: Double
        let playing: Bool
    }

    private let queue = DispatchQueue(label: "com.jsonify.minits.meeting-player", qos: .userInitiated)
    /// Only touched on `queue`.
    private var player: AVAudioPlayer?
    private var url: URL?

    /// Opens `url` if it isn't open yet and plays it from `from`; nil if it can't be opened.
    func play(url: URL, from: Double, rate: Float) async -> Status? {
        await run {
            #if os(iOS)
            // Set every time: recording switches the session to .record.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio)
            try? session.setActive(true)
            #endif
            if self.player == nil || self.url != url {
                self.player?.stop()
                guard let player = try? AVAudioPlayer(contentsOf: url) else {
                    self.player = nil
                    self.url = nil
                    return nil
                }
                player.enableRate = true
                player.prepareToPlay()
                self.player = player
                self.url = url
            }
            guard let player = self.player else { return nil }
            player.rate = rate
            player.currentTime = min(max(from, 0), player.duration)
            player.play()
            return Self.status(of: player)
        }
    }

    func pause() async -> Status? {
        await run {
            guard let player = self.player else { return nil }
            player.pause()
            return Self.status(of: player)
        }
    }

    func seek(to time: Double) async -> Status? {
        await run {
            guard let player = self.player else { return nil }
            player.currentTime = min(max(time, 0), player.duration)
            return Self.status(of: player)
        }
    }

    func setRate(_ rate: Float) async {
        _ = await run { self.player?.rate = rate }
    }

    func status() async -> Status? {
        await run { self.player.map(Self.status(of:)) }
    }

    func stop() {
        queue.async {
            let wasOpen = self.player != nil
            self.player?.stop()
            self.player = nil
            self.url = nil
            #if os(iOS)
            if wasOpen { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
            #else
            _ = wasOpen
            #endif
        }
    }

    private static func status(of player: AVAudioPlayer) -> Status {
        Status(time: player.currentTime, duration: player.duration, playing: player.isPlaying)
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
