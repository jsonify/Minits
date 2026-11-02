import SK1Tokens
import SK1UI
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Screen A2: the meeting is being recorded. Keeps going with the screen locked.
///
/// SK-1 look: the meeting's title, one big LCD (REC lamp, kind and head count, the elapsed time in seven-segment
/// digits, the input level), notes, the marks as LCD chips in a sunken tray, and the transport keys. Mark is the one
/// orange key; End is charcoal with a red lamp and asks first, in an SK-1 sheet (`ConfirmSheet`).
///
/// On iPhone the recording also shows as a Live Activity on the lock screen and in the Dynamic Island
/// (`RecordingLiveActivity`), whose Pause/Resume and Mark keys come back here as `RecordingCommand`s.
struct RecordingView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.runsMeetingWork) private var runsMeetingWork
    @Query(sort: \Member.sortOrder) private var members: [Member]
    let meeting: Meeting

    @State private var recorder = AudioRecorder()
    @State private var liveActivity = RecordingLiveActivity()
    @State private var startError: String?
    @State private var confirmingEnd = false

    private let marksEnd = "marks-end"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SKCaption(meeting.title)

            lcd

            notes

            marks

            Text("The transcript and who said what are worked out on this device after you end the meeting.")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)

            transport
        }
        .padding(20)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sk1Chassis()
        .navigationTitle("")
        .inlineTitle()
        .navigationBarBackButtonHiddenCompat()
        .task {
            guard runsMeetingWork else { return }
            await begin()
        }
        .onDisappear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
            liveActivity.end()
        }
        .onChange(of: recorder.isPaused) { updateLiveActivity() }
        .onChange(of: recorder.wasInterrupted) { updateLiveActivity() }
        .onChange(of: meeting.motionMarks.count) { updateLiveActivity() }
        .onReceive(NotificationCenter.default.publisher(for: .minitsRecordingCommand)) { note in
            guard recorder.isRecording, let raw = note.object as? String, let command = RecordingCommand(rawValue: raw)
            else { return }
            switch command {
            case .togglePause:
                Task {
                    if recorder.isPaused { await recorder.resume() } else { await recorder.pause() }
                }
            case .mark:
                markMotion()
            }
        }
        .confirmSheet(
            isPresented: $confirmingEnd,
            title: "End the meeting?",
            message: "Minits will stop recording and start working out who said what. You can't add to this recording afterwards.",
            readout: endReadout,
            confirmTitle: "End and make the transcript",
            tone: .stop,
            cancelTitle: "Keep recording"
        ) {
            Task { await end() }
        }
    }

    /// What's been recorded, on the End sheet's LCD: "01:13 RECORDED · 2 MOMENTS".
    private var endReadout: String {
        let count = meeting.motionMarks.count
        let marks = count == 0 ? "NO \(markName.uppercased())S" : "\(count) \(markName.uppercased())\(count == 1 ? "" : "S")"
        return "\(SK1.Format.elapsed(recorder.elapsed)) RECORDED · \(marks)"
    }

    private var present: [Member] { members.filter { meeting.attendeeIDs.contains($0.id) } }

    /// "Motion" or "Moment".
    private var markName: String { meeting.kind.markName.capitalized }

    // MARK: - LCD

    private var lcd: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        let recording = recorder.isRecording && !recorder.isPaused
        return SKLCD {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    SKLamp(color: .red, lit: recording, glow: 4, size: 7, label: "Recording", blinking: true)
                    Text(SK1.Format.elapsedStatus(paused: recorder.isPaused))
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                    Spacer(minLength: 8)
                    Text("\(meeting.kind.shortName) · \(present.count) HERE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .lineLimit(1)
                }
                .foregroundStyle(ink)

                SKSevenSegment(SK1.Format.elapsed(recorder.elapsed), digitHeight: 52, spacing: 5)
                    .shadow(color: ink.opacity(0.15), radius: 0, x: 1, y: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                SKLevelMeter(levels: recorder.levelHistory, height: 40)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lcdAccessibilityLabel))
    }

    private var lcdAccessibilityLabel: String {
        let timer = SK1.Format.elapsedAccessibilityLabel(
            seconds: recorder.elapsed, recording: recorder.isRecording, paused: recorder.isPaused)
        return "\(timer), \(present.count) here"
    }

    // MARK: - Notes

    @ViewBuilder private var notes: some View {
        if recorder.wasInterrupted {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    SKLamp(color: .warning, lit: true, label: "Interrupted")
                    SKCaption("Interrupted")
                }
                Text("Paused by a call or another app. Tap Resume to keep going.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let startError {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                SKLamp(color: .danger, lit: true, label: "Error")
                Text(startError)
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if recorder.elapsed < 60 {
            Text("Let everyone know the meeting is being recorded.")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Marks

    private var marks: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption("Marked \(markName)s")
            SKWell {
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            if meeting.motionMarks.isEmpty {
                                Text(markHelp)
                                    .sk1Hint()
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                FlowLayout(spacing: 6) {
                                    ForEach(Array(meeting.motionMarks.enumerated()), id: \.offset) { index, mark in
                                        SKChip("\(markName.uppercased()) \(index + 1) · \(mark.clock)", height: 24)
                                            .accessibilityLabel(Text("\(markName) \(index + 1) marked at \(mark.clock)"))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(12)
                        Color.clear.frame(height: 0).id(marksEnd)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: meeting.motionMarks.count) {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(marksEnd, anchor: .bottom) }
                    }
                }
            }
            .frame(minHeight: 64, maxHeight: .infinity)
        }
    }

    private var markHelp: LocalizedStringKey {
        switch meeting.kind {
        case .board: return "Tap **Mark motion** whenever someone makes a motion or the board votes. Those spots get extra attention in the minutes."
        case .adHoc: return "Tap **Mark moment** when something important is decided or agreed. Those spots get extra attention in the summary."
        }
    }

    // MARK: - Transport

    private var transport: some View {
        SKKeyTray(caption: "Transport") {
            KeyRow(spacing: 3, weights: [1, 1.6, 1]) {
                Button {
                    Task {
                        if recorder.isPaused { await recorder.resume() } else { await recorder.pause() }
                    }
                } label: {
                    KeyLabel(recorder.isPaused ? "Resume" : "Pause",
                             systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.sk1Key(.cream, size: .large))
                .disabled(!recorder.isRecording)

                Button {
                    markMotion()
                } label: {
                    KeyLabel("Mark \(meeting.kind.markName)", systemImage: "bookmark.fill")
                }
                .buttonStyle(.sk1Key(.orange, size: .large))
                .disabled(!recorder.isRecording)

                Button {
                    confirmingEnd = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "stop.fill").font(.system(size: 16, weight: .semibold))
                        HStack(spacing: 5) {
                            SKLamp(color: .red, lit: true, glow: 3, size: 6)
                            Text("End").font(.system(size: 12, weight: .bold))
                        }
                    }
                }
                .buttonStyle(.sk1Key(.charcoal, size: .large))
                .accessibilityLabel(Text("End meeting"))
            }
            .frame(height: SK1KeySize.large.height)
        }
    }

    // MARK: - Actions

    private func begin() async {
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
            try await recorder.start(to: meeting.audioURL)
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
            liveActivity.start(title: meeting.title, kindName: meeting.kind.shortName, markName: markName,
                               present: present.count, marks: meeting.motionMarks.count)
        } catch {
            startError = error.localizedDescription
        }
    }

    private func markMotion() {
        meeting.motionMarks.append(recorder.elapsed)
        try? context.save()
    }

    private func updateLiveActivity() {
        liveActivity.update(isPaused: recorder.isPaused, wasInterrupted: recorder.wasInterrupted,
                            elapsed: recorder.elapsed, marks: meeting.motionMarks.count)
    }

    private func end() async {
        liveActivity.end()
        meeting.durationSeconds = await recorder.stop()
        meeting.status = .processing
        try? context.save()
        router.showMeeting(meeting)
    }
}

private extension MeetingKind {
    /// The kind as the LCD shows it: "BOARD" or "AD-HOC".
    var shortName: String {
        switch self {
        case .board: return "BOARD"
        case .adHoc: return "AD-HOC"
        }
    }
}

/// A tall key's face: its symbol over its title.
private struct KeyLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
    }
}

/// Lays its subviews out in a row, sharing the width in proportion to `weights` (one per subview).
private struct KeyRow: Layout {
    var spacing: CGFloat
    var weights: [CGFloat]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 320, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let total = subviews.indices.reduce(CGFloat(0)) { $0 + weight($1) }
        guard total > 0 else { return }
        let unit = max(bounds.width - gaps, 0) / total
        var x = bounds.minX
        for index in subviews.indices {
            let width = unit * weight(index)
            subviews[index].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                                  proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func weight(_ index: Int) -> CGFloat { index < weights.count ? weights[index] : 1 }
}

/// Lays its subviews out left to right, starting a new line when the next one doesn't fit.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row(indices: [index], width: size.width, height: size.height)
            } else {
                row.indices.append(index)
                row.width = needed
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

extension View {
    /// The recording screen has its own End button; Back would abandon a live recording.
    func navigationBarBackButtonHiddenCompat() -> some View {
        self.navigationBarBackButtonHidden(true)
    }
}
