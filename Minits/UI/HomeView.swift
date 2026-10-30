import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @AppStorage("modelsReady") private var modelsReady = false
    @AppStorage("lastMeetingKind") private var lastKind: MeetingKind = .board
    @State private var preparing = false
    @State private var prepareError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Minits")
                        .font(Theme.heading(34))
                        .foregroundStyle(Theme.ink)
                    Text("Record a meeting. Get minutes or a summary with names attached.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryInk)
                }

                startHero

                if !modelsReady { modelsCard }

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

    /// Pick the kind of meeting right here, so the first tap already says what you'll get.
    /// Roll call opens with that kind selected (it reads the same `lastMeetingKind`).
    private var startHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Start a meeting", systemImage: "mic.fill")
                    .font(Theme.heading(24))
                    .foregroundStyle(.white)
                Text("Pick the kind. Minits listens, works out who said what, and writes it up.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.onAccentSecondary)
            }
            ForEach(MeetingKind.allCases) { kind in
                Button {
                    lastKind = kind
                    router.path.append(.rollCall)
                } label: {
                    KindTile(kind: kind, isLastUsed: !meetings.isEmpty && kind == lastKind)
                }
                .buttonStyle(KindTileButtonStyle())
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24))
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

private struct KindTile: View {
    let kind: MeetingKind
    let isLastUsed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(kind.label)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if isLastUsed {
                        Text("Last used")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Theme.accentSoft, in: Capsule())
                    }
                }
                Text(kind.promise)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                // A taste of the write-up, so the choice is about the result, not the setting.
                Label(kind.sampleLine, systemImage: kind == .board ? "checkmark.seal.fill" : "lightbulb.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.motion)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.motionSoft, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("For example: \(kind.sampleLine)")
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.border)
                .padding(.top, 14)
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens roll call for a new \(kind.label.lowercased())")
    }
}

private struct KindTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension MeetingKind {
    var symbol: String {
        switch self {
        case .board: return "building.columns.fill"
        case .adHoc: return "bubble.left.and.bubble.right.fill"
        }
    }

    var promise: String {
        switch self {
        case .board: return "Formal minutes: attendance, motions with mover and vote, action items."
        case .adHoc: return "A plain summary: what was discussed, decisions, who does what next."
        }
    }

    var sampleLine: String {
        switch self {
        case .board: return "Motion carried 5–0, moved by the Treasurer"
        case .adHoc: return "Decided: launch Friday. Sam sends the invite."
        }
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
        case .ready: pill(meeting.minutes == nil ? "Transcript" : meeting.kind.documentName, Theme.success, Theme.successSoft)
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
