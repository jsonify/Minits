import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @AppStorage("modelsReady") private var modelsReady = false
    @State private var preparing = false
    @State private var prepareError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Minits")
                        .font(Theme.heading(34))
                        .foregroundStyle(Theme.ink)
                    Text("Record the board meeting. Get minutes with names attached.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryInk)
                }

                if !modelsReady { modelsCard }

                Button {
                    router.path.append(.rollCall)
                } label: {
                    Label("New meeting", systemImage: "mic.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                if meetings.isEmpty {
                    Text("Your meetings will show up here.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    Text("Past meetings")
                        .font(.system(size: 13, weight: .bold))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.secondaryInk)
                    ForEach(meetings) { meeting in
                        Button {
                            router.path.append(meeting.status == .recording ? .recording(meeting) : .meeting(meeting))
                        } label: {
                            MeetingRow(meeting: meeting)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete meeting", role: .destructive) { delete(meeting) }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ground)
        .navigationTitle("")
        .inlineTitle()
    }

    private var modelsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("One-time setup")
                .font(.system(size: 16, weight: .semibold))
            Text("Minits needs to download its voice and transcription models (a few hundred MB). After that, everything runs on this device, even with no internet. Wi-Fi recommended.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryInk)
            if let prepareError {
                Text(prepareError).font(.system(size: 14)).foregroundStyle(Theme.danger)
            }
            Button {
                Task { await prepare() }
            } label: {
                if preparing {
                    HStack(spacing: 8) { ProgressView(); Text("Downloading…") }
                } else {
                    Text("Download now")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(preparing)
        }
        .card()
    }

    private func prepare() async {
        preparing = true
        prepareError = nil
        do {
            try await VoiceEngine.shared.prepare()
            modelsReady = true
        } catch {
            prepareError = "Download didn't finish: \(error.localizedDescription)"
        }
        preparing = false
    }

    private func delete(_ meeting: Meeting) {
        try? FileManager.default.removeItem(at: meeting.audioURL)
        context.delete(meeting)
        try? context.save()
    }
}

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(meeting.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(meeting.durationSeconds.clock)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryInk)
            }
            Spacer()
            statusPill
            Image(systemName: "chevron.right")
                .foregroundStyle(Theme.border)
                .accessibilityHidden(true)
        }
        .card()
    }

    @ViewBuilder private var statusPill: some View {
        switch meeting.status {
        case .recording: pill("Recording", Theme.danger, Theme.dangerSoft)
        case .processing: pill("Working", Theme.accent, Theme.accentSoft)
        case .needsReview: pill("Review \(meeting.linesNeedingReview.count)", Theme.warning, Theme.motionSoft)
        case .ready: pill(meeting.minutes == nil ? "Transcript" : "Minutes", Theme.success, Theme.successSoft)
        case .failed: pill("Needs retry", Theme.danger, Theme.dangerSoft)
        }
    }

    private func pill(_ text: String, _ fg: Color, _ bg: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bg, in: Capsule())
    }
}
