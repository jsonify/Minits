import AVFoundation
import Foundation
import Observation

/// Plays a whole meeting recording for the Transcript tab's cassette deck: play, pause, stop, jump, volume and
/// speed, with the position, the two meter levels and which transcript line is playing.
///
/// Setting up the audio session can block for a moment, so that and opening the file happen on a background queue
/// (as `ClipPlayer` does). The ready player is then handed to the main actor, which drives it and reads it about
/// 30 times a second while it plays.
@MainActor
@Observable
final class MeetingPlayer {
    enum State: Equatable { case stopped, playing, paused }

    /// The transcript's lines as times, so the player can say which one is playing.
    struct Mark: Equatable {
        let id: UUID
        let start: Double
        let end: Double
    }

    private(set) var state: State = .stopped
    /// Where playback is, in seconds.
    private(set) var position: Double = 0
    /// How long the recording is, in seconds. Until the file is opened, this is the meeting's own duration.
    private(set) var duration: Double = 0
    /// The two meters, from 0 (at rest) to 1 (full scale), with VU ballistics. For a mono file the first is the
    /// average level and the second the peak; for a stereo file they're left and right.
    private(set) var levels: (Float, Float) = (0, 0)
    private(set) var isStereo = false
    /// The line under the playhead once playback has started, else nil.
    private(set) var currentLineID: UUID?
    /// Set when the recording couldn't be opened.
    private(set) var failed = false

    /// 0 to 1.
    var volume: Float = 1 { didSet { player?.volume = volume } }
    /// 0.5 to 2.
    var rate: Float = 1 { didSet { player?.rate = rate } }

    var marks: [Mark] = [] { didSet { updateCurrentLine() } }

    var isPlaying: Bool { state == .playing }
    /// How far through the recording, from 0 to 1.
    var progress: Double { duration > 0 ? min(max(position / duration, 0), 1) : 0 }

    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var tick: Task<Void, Never>?
    @ObservationIgnored private var opening = false
    @ObservationIgnored private var pendingStart: Double?
    @ObservationIgnored private let io = DeckIO()

    /// Points the deck at a recording, without opening it yet. `duration` shows until the file is opened.
    func load(url: URL, duration: Double) {
        guard self.url != url else { return }
        stop()
        player = nil
        self.url = url
        self.duration = max(duration, 0)
        failed = false
    }

    // MARK: Transport

    /// Plays from where it is, or from `start` seconds.
    func play(from start: Double? = nil) {
        if let player {
            if let start { player.currentTime = clamp(start) }
            player.rate = rate
            player.volume = volume
            player.play()
            setState(.playing)
            return
        }
        open(thenPlayFrom: start ?? position)
    }

    func pause() {
        guard state == .playing else { return }
        player?.pause()
        refresh()
        setState(.paused)
    }

    /// PAUSE latches: pressed while playing it pauses; pressed again it plays.
    func togglePause() {
        switch state {
        case .playing: pause()
        case .paused: play()
        case .stopped: break
        }
    }

    /// Stops and rewinds to the start.
    func stop() {
        player?.stop()
        player?.currentTime = 0
        pendingStart = nil
        position = 0
        setState(.stopped)
        updateCurrentLine()
    }

    /// Jumps `seconds` (negative to go back), staying playing or paused.
    func skip(_ seconds: Double) {
        seek(to: position + seconds)
    }

    func seek(to seconds: Double) {
        let target = clamp(seconds)
        player?.currentTime = target
        if player == nil, opening { pendingStart = target }
        position = target
        if state == .stopped, target > 0 { setState(.paused) }
        updateCurrentLine()
    }

    /// A line's play key: plays from just before the line, or pauses if that line is already playing.
    func toggleLine(_ mark: Mark) {
        if state == .playing, currentLineID == mark.id {
            pause()
        } else {
            // A little lead-in helps you recognize the voice.
            play(from: max(0, mark.start - 0.3))
        }
    }

    /// Shows the deck mid-meeting without any audio, for the screenshot tests: at `position` of `duration`, in
    /// `state`, with the meters at `levels`.
    func stage(position: Double, duration: Double, state: State, levels: (Float, Float)) {
        self.duration = duration
        self.position = position
        self.state = state
        self.levels = levels
        updateCurrentLine()
    }

    // MARK: Opening

    private func open(thenPlayFrom start: Double) {
        guard let url, !opening else {
            pendingStart = start
            return
        }
        opening = true
        pendingStart = start
        io.open(url: url) { [weak self] box in
            Task { @MainActor in self?.opened(box.player) }
        }
    }

    private func opened(_ newPlayer: AVAudioPlayer?) {
        opening = false
        guard let newPlayer else {
            failed = true
            setState(.stopped)
            return
        }
        player = newPlayer
        isStereo = newPlayer.numberOfChannels >= 2
        if newPlayer.duration > 0 { duration = newPlayer.duration }
        let start = clamp(pendingStart ?? position)
        pendingStart = nil
        newPlayer.currentTime = start
        newPlayer.volume = volume
        newPlayer.rate = rate
        newPlayer.play()
        position = start
        setState(.playing)
    }

    // MARK: Ticking

    private func setState(_ new: State) {
        if state != new { state = new }
        if new == .playing {
            startTicking()
        } else if tick == nil, levels != (0, 0) {
            // The meters still need to fall back to rest.
            startTicking()
        }
    }

    private func startTicking() {
        guard tick == nil else { return }
        tick = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, self.step() else { break }
            }
            self?.tick = nil
        }
    }

    /// One tick: reads the position and the meters. Returns whether to keep ticking.
    private func step() -> Bool {
        if state == .playing {
            if let player, !player.isPlaying {
                // It reached the end.
                position = duration
                setState(.paused)
            } else {
                refresh()
            }
        }
        var targets: (Float, Float) = (0, 0)
        if state == .playing, let player {
            player.updateMeters()
            if isStereo {
                targets = (Self.meterLevel(player.averagePower(forChannel: 0)),
                           Self.meterLevel(player.averagePower(forChannel: 1)))
            } else {
                targets = (Self.meterLevel(player.averagePower(forChannel: 0)),
                           Self.meterLevel(player.peakPower(forChannel: 0)))
            }
        }
        let next = (Self.ease(levels.0, to: targets.0), Self.ease(levels.1, to: targets.1))
        if next != levels { levels = next }
        return state == .playing || levels != (0, 0)
    }

    private func refresh() {
        guard let player else { return }
        let now = player.currentTime
        if abs(now - position) > 0.001 { position = now }
        updateCurrentLine()
    }

    private func updateCurrentLine() {
        let id: UUID?
        if state == .stopped {
            id = nil
        } else {
            id = marks.last { position >= $0.start - 0.35 && position < $0.end }?.id
        }
        if id != currentLineID { currentLineID = id }
    }

    private func clamp(_ seconds: Double) -> Double {
        min(max(seconds, 0), max(duration - 0.05, 0))
    }

    // MARK: Meter maths

    /// A meter's level (0 to 1 across the scale) for a power in dBFS. 0 VU is set at -18 dBFS, so ordinary speech
    /// sits just below 0; the scale runs from -20 VU to +3 VU and is linear in amplitude, as a real VU meter's is.
    nonisolated static func meterLevel(_ dbfs: Float) -> Float {
        let vu = dbfs + 18
        return VUScale.fraction(vu: vu)
    }

    /// VU ballistics at 30 ticks a second: about 300 ms to reach a new level, falling back a little slower.
    nonisolated static func ease(_ current: Float, to target: Float) -> Float {
        let next = current + (target - current) * (target > current ? 0.3 : 0.18)
        return abs(next - target) < 0.002 ? target : next
    }
}

/// Where a VU reading falls across the meter's scale, from 0 at -20 VU to 1 at +3 VU. The scale is linear in
/// amplitude, so 0 VU sits about 70% across, as on a real meter.
enum VUScale {
    static let lowest: Float = -20
    static let highest: Float = 3

    static func fraction(vu: Float) -> Float {
        let lo = amplitude(lowest), hi = amplitude(highest)
        guard vu > lowest else { return 0 }
        return min(max((amplitude(vu) - lo) / (hi - lo), 0), 1)
    }

    private static func amplitude(_ vu: Float) -> Float { powf(10, vu / 20) }
}

/// Carries a player across from the background queue.
private struct PlayerBox: @unchecked Sendable { let player: AVAudioPlayer? }

/// Sets up the audio session and opens the file on a serial background queue.
private final class DeckIO: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.jsonify.minits.deck", qos: .userInitiated)

    func open(url: URL, done: @escaping @Sendable (PlayerBox) -> Void) {
        queue.async {
            #if os(iOS)
            // Set every time: recording switches the session to .record.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio)
            try? session.setActive(true)
            #endif
            guard let player = try? AVAudioPlayer(contentsOf: url) else {
                done(PlayerBox(player: nil))
                return
            }
            player.enableRate = true
            player.isMeteringEnabled = true
            player.prepareToPlay()
            done(PlayerBox(player: player))
        }
    }
}
