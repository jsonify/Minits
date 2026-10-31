import SK1Tokens
import SK1UI
import SwiftData
import SwiftUI

/// Screen A0: the meetings so far, and where a new one starts.
///
/// SK-1 look: an LCD header (name, status, the meeting count in seven-segment digits), a tray with one key per kind of
/// meeting (the last one used is lit with SK-1's orange "on" bar), the one-time model download when it's needed, and
/// the past meetings as rows in one sunken tray, each with a status lamp. Picking a kind saves it as the last used and
/// opens roll call with it selected.
struct HomeView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Meeting.startedAt, order: .reverse) private var meetings: [Meeting]
    @AppStorage("modelsReady") private var modelsReady = false
    @AppStorage("lastMeetingKind") private var lastKind: MeetingKind = .board
    @State private var preparing = false
    @State private var prepareError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SKCaption("Minits · MN-1")

                header

                Text("Record a meeting. Get minutes or a summary with names attached.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)

                startTray

                if !modelsReady { setup }

                pastMeetings
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .sk1Chassis()
        .navigationTitle("")
        .inlineTitle()
    }

    private var palette: SK1.Palette { SK1.palette(for: scheme) }

    // MARK: - Header

    private var header: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        let count = meetings.count
        return SKLCD {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("MINITS")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    SKSevenSegment(String(format: "%02d", count), digitHeight: 30, spacing: 4)
                        .shadow(color: ink.opacity(0.15), radius: 0, x: 1, y: 1)
                        .opacity(count == 0 ? 0.4 : 1)
                    Text("MEETINGS")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(headerAccessibilityLabel))
    }

    private var statusLine: String {
        if !modelsReady { return "MODELS NOT DOWNLOADED" }
        return meetings.isEmpty ? "NO MEETINGS YET" : "ON-DEVICE · MODELS READY"
    }

    private var headerAccessibilityLabel: String {
        let count = meetings.count
        let counted = count == 0 ? "no meetings yet" : count == 1 ? "1 meeting" : "\(count) meetings"
        return "Minits, \(counted), models \(modelsReady ? "ready" : "not downloaded")"
    }

    // MARK: - Start a meeting

    private var startTray: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption("Start a meeting")
            SKWell {
                VStack(alignment: .leading, spacing: 14) {
                    kindGroup(.board)
                    SKGroove()
                    kindGroup(.adHoc)
                }
                .padding(12)
            }
        }
    }

    private func kindGroup(_ kind: MeetingKind) -> some View {
        let isLast = !meetings.isEmpty && lastKind == kind
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                lastKind = kind
                router.path.append(.rollCall)
            } label: {
                Label(kind.label, systemImage: kind.symbol)
            }
            .buttonStyle(.sk1Key(.cream, isOn: isLast, size: .large))
            .accessibilityValue(Text(isLast ? "Last used" : ""))
            .accessibilityHint(Text("Opens roll call for a new \(kind.label.lowercased())"))

            Text(kind.promise)
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)

            // The example is long: on a narrow screen it shrinks a little rather than being cut off.
            HStack(spacing: 0) {
                SKChip(kind.example.uppercased(), height: 22)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel(Text("For example: \(kind.example)"))
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - One-time setup

    private var setup: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption("One-time setup")
            SKWell {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Minits needs to download its voice and transcription models (a few hundred MB). After that, everything runs on this device, even with no internet. Wi-Fi recommended.")
                        .sk1Hint()
                        .fixedSize(horizontal: false, vertical: true)
                    if let prepareError {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            SKLamp(color: .danger, lit: true, label: "Error")
                            Text(prepareError)
                                .sk1Hint()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if preparing {
                        // VoiceEngine.prepare() reports no progress, so this is a status, not a bar.
                        SKReadout("DOWNLOADING MODELS…")
                    }
                    Button("Download now") {
                        Task { await prepare() }
                    }
                    .buttonStyle(.sk1Key(.cream))
                    .disabled(preparing)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Past meetings

    @ViewBuilder private var pastMeetings: some View {
        if meetings.isEmpty {
            Text("Your meetings will show up here.")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                SKCaption("Past meetings")
                SKWell {
                    VStack(spacing: 0) {
                        ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                            if index > 0 { SKGroove() }
                            row(meeting)
                        }
                    }
                }
                Text("Everything stays on this device.")
                    .sk1Hint()
            }
        }
    }

    private func row(_ meeting: Meeting) -> some View {
        let status = meeting.rowStatus
        let ink = Color(sk1Hex: palette.ink)
        return Button {
            router.path.append(meeting.status == .recording ? .recording(meeting) : .meeting(meeting))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                    Text(meeting.dateLine)
                        .sk1Hint()
                    HStack(spacing: 6) {
                        SKLamp(color: status.color, lit: true, glow: 3, size: 7, label: status.text, blinking: status.blinking)
                            .accessibilityHidden(true)
                        Text(status.text)
                            .font(.sk1(SK1.TypeScale.indicator))
                            .tracking(SK1.TypeScale.indicator.kern)
                            .textCase(.uppercase)
                            .foregroundStyle(Color(sk1Hex: palette.ink))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                SKChip(meeting.durationSeconds.clock)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(meeting.title), \(meeting.dateLine), \(status.text), \(SK1.Format.spokenDuration(meeting.durationSeconds))"))
        .contextMenu {
            Button("Delete meeting", role: .destructive) { delete(meeting) }
        }
    }

    // MARK: - Actions

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

/// What a row's status line shows: a lamp and the words that carry its meaning.
private struct RowStatus {
    let text: String
    let color: SKLampColor
    let blinking: Bool
}

private extension Meeting {
    var rowStatus: RowStatus {
        switch status {
        case .recording: return RowStatus(text: "Recording", color: .red, blinking: true)
        case .processing: return RowStatus(text: "Working", color: .teal, blinking: true)
        case .needsReview: return RowStatus(text: "\(linesNeedingReview.count) to review", color: .warning, blinking: false)
        case .ready:
            let text = minutes == nil ? "Transcript ready" : "\(kind.documentName) ready"
            return RowStatus(text: text, color: .teal, blinking: false)
        case .failed: return RowStatus(text: "Needs retry", color: .danger, blinking: false)
        }
    }

    /// "Oct 14 · 7:00 PM", with " · Ad-hoc" for an ad-hoc meeting.
    var dateLine: String {
        let day = startedAt.formatted(.dateTime.month(.abbreviated).day())
        let time = startedAt.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(time)" + (kind == .adHoc ? " · Ad-hoc" : "")
    }
}

private extension MeetingKind {
    var symbol: String {
        switch self {
        case .board: return "building.columns.fill"
        case .adHoc: return "bubble.left.and.bubble.right.fill"
        }
    }

    /// What this kind gets you.
    var promise: String {
        switch self {
        case .board: return "Formal minutes: attendance, motions with mover and vote, action items."
        case .adHoc: return "A plain summary: what was discussed, decisions, who does what next."
        }
    }

    /// A line from the result, in normal case (the chip shows it in capitals).
    var example: String {
        switch self {
        case .board: return "Motion carried 5–0, moved by the treasurer"
        case .adHoc: return "Decided: launch Friday. Sam sends the invite."
        }
    }
}
