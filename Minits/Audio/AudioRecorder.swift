import AVFoundation
import Foundation
import Observation

/// Records 16 kHz mono WAV, which is exactly what FluidAudio's models want,
/// so no conversion is needed later. Works for both voice samples and full meetings.
///
/// The recorder itself and the audio session live on a background queue (`RecorderIO`): activating the session can
/// block for a moment, and `AVAudioRecorder` touches the session from whichever thread calls it, so calling either
/// from the main thread can make the UI stutter (AVAudioSession warns about exactly that). This class keeps the
/// state the screens show, on the main actor.
@MainActor
@Observable
final class AudioRecorder: NSObject {
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    /// 0…1 loudness, for the waveform.
    private(set) var level: Float = 0
    /// Recent levels, newest last, for drawing bars.
    private(set) var levelHistory: [Float] = Array(repeating: 0, count: 40)
    private(set) var wasInterrupted = false

    private let io = RecorderIO()
    @ObservationIgnored private var timer: Timer?
    /// Set while a meter reading is on its way back, so slow readings don't pile up.
    @ObservationIgnored private var metering = false

    // MARK: Permission

    enum Permission: Sendable, Equatable {
        case undetermined, granted, denied
    }

    /// Whether Minits may use the microphone, without asking.
    nonisolated static var permission: Permission {
        #if os(iOS)
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .undetermined
        default: return .denied
        }
        #endif
    }

    static func requestPermission() async -> Bool {
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
        #endif
    }

    // MARK: Control

    func start(to url: URL) async throws {
        try await io.start(url: url)
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        #endif
        isRecording = true
        isPaused = false
        wasInterrupted = false
        elapsed = 0
        levelHistory = Array(repeating: 0, count: levelHistory.count)
        startTimer()
    }

    func pause() async {
        isPaused = true
        await io.pause()
    }

    func resume() async {
        await io.resume()
        isPaused = false
        wasInterrupted = false
    }

    /// Stops and returns the recorded duration in seconds.
    @discardableResult
    func stop() async -> TimeInterval {
        timer?.invalidate()
        timer = nil
        isRecording = false
        isPaused = false
        level = 0
        #if os(iOS)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        #endif
        let duration = await io.stop() ?? elapsed
        return max(duration, elapsed)
    }

    // MARK: Metering

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() async {
        guard isRecording, !metering else { return }
        metering = true
        defer { metering = false }
        guard let reading = await io.meter(), isRecording else { return }
        if !isPaused { elapsed = reading.time }
        let normalized = isPaused ? 0 : max(0, min(1, (reading.power + 50) / 50))   // power is -160…0 dB
        level = normalized
        levelHistory.removeFirst()
        levelHistory.append(normalized)
    }

    #if os(iOS)
    @objc nonisolated private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        Task { @MainActor in
            if type == .began {
                self.isPaused = true
                self.wasInterrupted = true
            }
        }
    }
    #endif

    enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "The microphone couldn't start recording." }
    }
}

/// The `AVAudioRecorder` and the audio session, used only on one serial background queue. Each call waits for its
/// work, so calls run in the order they're made.
private final class RecorderIO: @unchecked Sendable {
    struct Meter: Sendable {
        let time: TimeInterval
        let power: Float
    }

    private let queue = DispatchQueue(label: "com.jsonify.minits.recorder", qos: .userInitiated)
    /// Only touched on `queue`.
    private var recorder: AVAudioRecorder?

    func start(url: URL) async throws {
        try await run {
            #if os(iOS)
            try Self.activateSession()
            #endif
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { throw AudioRecorder.RecorderError.couldNotStart }
            self.recorder = recorder
        }
    }

    func pause() async {
        try? await run { self.recorder?.pause() }
    }

    func resume() async {
        _ = try? await run {
            #if os(iOS)
            // After an interruption the system may have deactivated the session.
            try? Self.activateSession()
            #endif
            self.recorder?.record()
        }
    }

    /// Stops, releases the session and returns how long the recording is (nil if nothing was recording).
    func stop() async -> TimeInterval? {
        let duration: TimeInterval?? = try? await run {
            let duration = self.recorder?.currentTime
            self.recorder?.stop()
            self.recorder = nil
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            return duration
        }
        return duration ?? nil
    }

    func meter() async -> Meter? {
        let reading: Meter?? = try? await run {
            guard let recorder = self.recorder else { return nil }
            recorder.updateMeters()
            return Meter(time: recorder.currentTime, power: recorder.averagePower(forChannel: 0))
        }
        return reading ?? nil
    }

    #if os(iOS)
    /// .record + .default mode: no voice processing, so voices across the table aren't filtered out.
    /// Wired/USB conference mics are picked up automatically when plugged in.
    private static func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
    }
    #endif

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }
}
