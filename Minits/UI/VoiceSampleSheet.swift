import SK1Tokens
import SK1UI
import SwiftData
import SwiftUI

/// Records ~10 seconds of one member and turns it into a voiceprint with FluidAudio.
///
/// SK-1 look, like the Recording screen: an LCD with a status lamp, the member's name and role, the elapsed time in
/// seven-segment digits and the input level; the line to read in a sunken tray; a note on what's happening; and the
/// keys in a tray. Record is the one orange key; Stop is charcoal with a red lamp and works after 4 seconds.
struct VoiceSampleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @AppStorage("modelsReady") private var modelsReady = false

    let member: Member
    let others: [Member]

    @State private var recorder = AudioRecorder()
    @State private var phase: Phase = .ready
    @State private var sampleURL: URL?
    @State private var lookAlike: String?

    private let targetSeconds: TimeInterval = 10
    private let maxSeconds: TimeInterval = 15
    private let minSeconds: TimeInterval = 4

    enum Phase: Equatable {
        case ready, recording, learning, done, failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                lcd

                script

                status

                Spacer(minLength: 0)

                keys
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sk1Chassis()
            .navigationTitle("Voice sample")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .done ? "Done" : "Cancel") { close() }
                        .disabled(phase == .learning)
                }
            }
            .interactiveDismissDisabled(phase == .recording || phase == .learning)
            .onChange(of: recorder.elapsed) { _, elapsed in
                if phase == .recording, elapsed >= maxSeconds { Task { await finish() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
    }

    private var palette: SK1.Palette { SK1.palette(for: scheme) }

    // MARK: - LCD

    private var lcd: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        let lamp = phase.lamp
        return SKLCD {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    SKLamp(color: lamp.color, lit: lamp.lit, glow: 4, size: 7, label: lamp.word, blinking: lamp.blinking)
                    Text(lamp.word.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                    Spacer(minLength: 8)
                    Text("VOICE SAMPLE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .lineLimit(1)
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.name.uppercased())
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if !member.role.isEmpty {
                            Text(member.role.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(0.8)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        SKSevenSegment(SK1.Format.elapsed(recorder.elapsed), digitHeight: 30, spacing: 4)
                            .shadow(color: ink.opacity(0.15), radius: 0, x: 1, y: 1)
                            .opacity(phase == .recording ? 1 : 0.4)
                        Text("ABOUT \(SK1.Format.elapsed(targetSeconds))")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1)
                    }
                }

                SKLevelMeter(levels: recorder.levelHistory, height: 36)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lcdAccessibilityLabel))
    }

    private var lcdAccessibilityLabel: String {
        var parts = [member.name]
        if !member.role.isEmpty { parts.append(member.role) }
        parts.append(phase.lamp.word)
        if phase == .recording { parts.append(SK1.Format.spokenDuration(recorder.elapsed)) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Script

    private var script: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption("Say something like")
            SKWell {
                Text("“Hi, I'm \(member.name)\(member.role.isEmpty ? "" : ", the board's \(member.role.lowercased())"). I've been on the board for a while and I'm here for tonight's meeting.”")
                    .font(.system(size: 17))
                    .italic()
                    .foregroundStyle(Color(sk1Hex: palette.ink))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Status

    @ViewBuilder private var status: some View {
        switch phase {
        case .ready:
            Text("Hold the phone about a foot away, like it'll sit during the meeting.")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
        case .recording:
            Text("Listening. Keep talking for about \(targetSeconds.clock); Stop works after \(minSeconds.clock).")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
        case .learning:
            VStack(alignment: .leading, spacing: 6) {
                SKReadout(modelsReady ? "LEARNING \(firstName.uppercased())'S VOICE…" : "DOWNLOADING VOICE MODELS…")
                if !modelsReady {
                    Text("First time only. After this, everything runs on this device.")
                        .sk1Hint()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .done:
            VStack(alignment: .leading, spacing: 8) {
                note(.success, "Voice saved", "\(firstName)'s voice is saved on this device.")
                if let lookAlike {
                    note(.warning, "Sounds alike",
                         "\(firstName) sounds a lot like \(lookAlike). That's OK, but lines between them may need a quick check after the meeting. A longer sample can help.")
                }
            }
        case .failed(let message):
            note(.danger, "Error", message)
        }
    }

    /// A lamp and caption, with a sentence under them.
    private func note(_ color: SKLampColor, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SKLamp(color: color, lit: true, label: title)
                SKCaption(title)
            }
            Text(text)
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Keys

    private var keys: some View {
        SKKeyTray(caption: "Sample") {
            switch phase {
            case .ready, .failed:
                Button {
                    Task { await start() }
                } label: {
                    Label(phase == .ready ? "Record \(firstName)'s sample" : "Try again", systemImage: "mic.fill")
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(.sk1Key(.orange, size: .large))
            case .recording:
                Button {
                    Task { await finish() }
                } label: {
                    HStack(spacing: 8) {
                        SKLamp(color: .red, lit: true, glow: 3, size: 6)
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
                .buttonStyle(.sk1Key(.charcoal, size: .large))
                .disabled(recorder.elapsed < minSeconds)
                .accessibilityLabel(Text("Stop"))
            case .learning:
                Button("Working…") {}
                    .buttonStyle(.sk1Key(.cream, size: .large))
                    .disabled(true)
            case .done:
                Button("Re-record") { phase = .ready }
                    .buttonStyle(.sk1Key(.cream, size: .large))
                Button("Done") { close() }
                    .buttonStyle(.sk1Key(.orange, size: .large))
            }
        }
    }

    private var firstName: String {
        member.name.split(separator: " ").first.map(String.init) ?? member.name
    }

    private func start() async {
        guard await AudioRecorder.requestPermission() else {
            phase = .failed("Minits can't use the microphone. Turn it on in Settings › Privacy › Microphone.")
            return
        }
        let url = Storage.temporaryRecordingURL()
        do {
            try recorder.start(to: url)
            sampleURL = url
            phase = .recording
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func finish() async {
        guard phase == .recording, let url = sampleURL else { return }
        recorder.stop()
        phase = .learning
        do {
            let embedding = try await VoiceEngine.shared.voiceprint(forSampleAt: url)
            modelsReady = true
            member.embedding = embedding
            member.voiceSavedAt = Date()
            try? context.save()
            lookAlike = others
                .compactMap { other -> (String, Float)? in
                    guard let theirs = other.embedding else { return nil }
                    return (other.name, VoiceEngine.similarity(embedding, theirs))
                }
                .filter { $0.1 > 0.60 }
                .max { $0.1 < $1.1 }?.0
            phase = .done
        } catch {
            phase = .failed(error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: url)
    }

    private func close() {
        if recorder.isRecording { recorder.stop() }
        if let sampleURL { try? FileManager.default.removeItem(at: sampleURL) }
        dismiss()
    }
}

/// What the LCD's lamp shows in each phase.
private struct PhaseLamp {
    let color: SKLampColor
    let lit: Bool
    let blinking: Bool
    let word: String
}

private extension VoiceSampleSheet.Phase {
    var lamp: PhaseLamp {
        switch self {
        case .ready: return PhaseLamp(color: .teal, lit: false, blinking: false, word: "Ready")
        case .recording: return PhaseLamp(color: .red, lit: true, blinking: true, word: "Recording")
        case .learning: return PhaseLamp(color: .teal, lit: true, blinking: true, word: "Learning")
        case .done: return PhaseLamp(color: .success, lit: true, blinking: false, word: "Saved")
        case .failed: return PhaseLamp(color: .danger, lit: true, blinking: false, word: "Error")
        }
    }
}
