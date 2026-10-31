import AVFoundation
import Foundation
import Observation

/// Records 16 kHz mono WAV, which is exactly what FluidAudio's models want,
/// so no conversion is needed later. Works for both voice samples and full meetings.
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

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    /// The last `stop()`'s session deactivation, which `start` waits for so it can't land after a new activation.
    private var deactivation: Task<Void, Never>?

    static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    // MARK: Permission

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

    /// Activating the audio session can block for a moment, so it happens off the main thread
    /// (AVAudioSession warns that doing it on the main thread can make the UI unresponsive).
    func start(to url: URL) async throws {
        #if os(iOS)
        await deactivation?.value
        deactivation = nil
        try await Self.activateSession()
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        #endif

        let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart }
        self.recorder = recorder
        isRecording = true
        isPaused = false
        wasInterrupted = false
        elapsed = 0
        levelHistory = Array(repeating: 0, count: levelHistory.count)
        startTimer()
    }

    func pause() {
        recorder?.pause()
        isPaused = true
    }

    func resume() async {
        #if os(iOS)
        // After an interruption the session may have been deactivated by the system.
        try? await Self.activateSession()
        #endif
        recorder?.record()
        isPaused = false
        wasInterrupted = false
    }

    /// Stops and returns the recorded duration in seconds.
    @discardableResult
    func stop() -> TimeInterval {
        let duration = recorder?.currentTime ?? elapsed
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
        isPaused = false
        level = 0
        #if os(iOS)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        deactivation = Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
        return max(duration, elapsed)
    }

    #if os(iOS)
    /// .record + .default mode: no voice processing, so voices across the table aren't filtered out.
    /// Wired/USB conference mics are picked up automatically when plugged in.
    private nonisolated static func activateSession() async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        }.value
    }
    #endif

    // MARK: Metering

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let recorder, isRecording else { return }
        if !isPaused { elapsed = recorder.currentTime }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)          // -160…0
        let normalized = isPaused ? 0 : max(0, min(1, (db + 50) / 50))
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
