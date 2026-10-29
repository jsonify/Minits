import SwiftData
import SwiftUI

/// Records ~10 seconds of one member and turns it into a voiceprint with FluidAudio.
struct VoiceSampleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
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
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Avatar(initials: member.initials, colorIndex: 0, size: 56)
                    Text(member.name).font(Theme.heading(28))
                    if !member.role.isEmpty {
                        Text(member.role).font(.system(size: 15)).foregroundStyle(Theme.secondaryInk)
                    }
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Say something like")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondaryInk)
                    Text("“Hi, I'm \(member.name)\(member.role.isEmpty ? "" : ", the board's \(member.role.lowercased())"). I've been on the board for a while and I'm here for tonight's meeting.”")
                        .font(.system(size: 17))
                        .italic()
                }
                .card()

                LevelBars(levels: recorder.levelHistory, height: 44)
                    .frame(maxWidth: .infinity)

                status

                Spacer()

                actionButton
            }
            .padding(20)
            .background(Theme.ground)
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

    @ViewBuilder private var status: some View {
        switch phase {
        case .ready:
            Text("Hold the phone about a foot away, like it'll sit during the meeting.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
        case .recording:
            Text("Listening… \(recorder.elapsed.clock) of about \(targetSeconds.clock)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.danger)
                .monospacedDigit()
        case .learning:
            HStack(spacing: 8) {
                ProgressView()
                Text(modelsReady ? "Learning \(firstName)'s voice…" : "Downloading voice models (first time only)…")
            }
            .font(.system(size: 15))
            .foregroundStyle(Theme.secondaryInk)
        case .done:
            VStack(spacing: 8) {
                Label("Voice saved", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.success)
                if let lookAlike {
                    Text("\(firstName) sounds a lot like \(lookAlike). That's OK, but lines between them may need a quick check after the meeting. A longer sample can help.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.warning)
                        .multilineTextAlignment(.center)
                }
            }
        case .failed(let message):
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Theme.danger)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch phase {
        case .ready, .failed:
            Button {
                Task { await start() }
            } label: {
                Label(phase == .ready ? "Record \(firstName)'s sample" : "Try again", systemImage: "mic.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        case .recording:
            Button {
                Task { await finish() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.danger))
            .disabled(recorder.elapsed < minSeconds)
        case .learning:
            Button("Working…") {}
                .buttonStyle(PrimaryButtonStyle())
                .disabled(true)
        case .done:
            HStack(spacing: 10) {
                Button("Re-record") { phase = .ready }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Done") { close() }
                    .buttonStyle(PrimaryButtonStyle())
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
