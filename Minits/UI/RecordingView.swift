import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Screen A2: the meeting is being recorded. Keeps going with the screen locked.
struct RecordingView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Member.sortOrder) private var members: [Member]
    let meeting: Meeting

    @State private var recorder = AudioRecorder()
    @State private var startError: String?
    @State private var confirmingEnd = false
    @State private var flashMark = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            consentNote

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(recorder.isPaused ? "Paused" : "Listening")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC9DAEA))
                    Spacer()
                    Text("\(present.count) here")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC9DAEA))
                }
                LevelBars(levels: recorder.levelHistory, color: .white, height: 40)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))

            if recorder.wasInterrupted {
                Text("Recording paused by a call or another app. Tap Resume to keep going.")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.danger)
            }
            if let startError {
                Text(startError).font(.system(size: 14)).foregroundStyle(Theme.danger)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if meeting.motionMarks.isEmpty {
                        Text(markHelp)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    ForEach(Array(meeting.motionMarks.enumerated()), id: \.offset) { index, mark in
                        Label("\(meeting.kind.markName.capitalized) \(index + 1) marked at \(mark.clock)", systemImage: "bookmark.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.motion)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .background(Theme.motionSoft, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("The transcript and speaker names are worked out on this device after you end the meeting.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.top, 6)
                }
            }

            controls
        }
        .padding(20)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
        .navigationTitle("")
        .inlineTitle()
        .navigationBarBackButtonHiddenCompat()
        .task { begin() }
        .onDisappear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
        }
        .confirmationDialog("End the meeting?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End and make the transcript") { end() }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("Minits will stop recording and start working out who said what.")
        }
    }

    private var present: [Member] { members.filter { meeting.attendeeIDs.contains($0.id) } }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryInk)
                Text(recorder.elapsed.longClock)
                    .font(Theme.heading(34))
                    .monospacedDigit()
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(recorder.isPaused ? Theme.secondaryInk : Theme.danger).frame(width: 8, height: 8)
                Text(recorder.isPaused ? "Paused" : "Recording")
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(recorder.isPaused ? Theme.secondaryInk : Theme.danger)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(recorder.isPaused ? Theme.hairline : Theme.dangerSoft, in: Capsule())
        }
    }

    @ViewBuilder private var consentNote: some View {
        if recorder.elapsed < 60 {
            Label("Let everyone know the meeting is being recorded.", systemImage: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryInk)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                recorder.isPaused ? recorder.resume() : recorder.pause()
            } label: {
                Label(recorder.isPaused ? "Resume" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                markMotion()
            } label: {
                Label("Mark \(meeting.kind.markName)", systemImage: "bookmark.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.motion)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.motionSoft.opacity(flashMark ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!recorder.isRecording)

            Button {
                confirmingEnd = true
            } label: {
                Label("End", systemImage: "stop.fill")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.danger))
            .frame(maxWidth: 110)
        }
    }

    private var markHelp: LocalizedStringKey {
        switch meeting.kind {
        case .board: return "Tap **Mark motion** whenever someone makes a motion or the board votes. Those spots get extra attention in the minutes."
        case .adHoc: return "Tap **Mark moment** when something important is decided or agreed. Those spots get extra attention in the summary."
        }
    }

    private func begin() {
        guard !recorder.isRecording, meeting.status == .recording else { return }
        // Reopened after the app was closed mid-meeting: keep what was recorded and process it.
        if let size = try? FileManager.default.attributesOfItem(atPath: meeting.audioURL.path)[.size] as? Int,
           size > 64_000 {
            meeting.durationSeconds = Double(size) / 32_000   // 16 kHz × 16-bit mono
            meeting.status = .processing
            try? context.save()
            router.showMeeting(meeting)
            return
        }
        do {
            try recorder.start(to: meeting.audioURL)
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        } catch {
            startError = error.localizedDescription
        }
    }

    private func markMotion() {
        meeting.motionMarks.append(recorder.elapsed)
        try? context.save()
        withAnimation(.easeOut(duration: 0.15)) { flashMark = true }
        withAnimation(.easeIn(duration: 0.3).delay(0.15)) { flashMark = false }
    }

    private func end() {
        meeting.durationSeconds = recorder.stop()
        meeting.status = .processing
        try? context.save()
        router.showMeeting(meeting)
    }
}

extension View {
    /// The recording screen has its own End button; Back would abandon a live recording.
    func navigationBarBackButtonHiddenCompat() -> some View {
        self.navigationBarBackButtonHidden(true)
    }
}
