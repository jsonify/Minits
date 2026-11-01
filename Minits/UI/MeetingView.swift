import SK1Tokens
import SK1UI
import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// After the meeting: processing, then Review (A3), Transcript and Minutes or Summary (A4).
///
/// SK-1 look: while processing, an LCD with a blinking WORKING lamp, the stage, how far along it is in seven-segment
/// digits and a bar of LCD cells. If processing fails, a red lamp and the error in a sunken tray, and an orange Try
/// again key. Once done, the tabs are an SK-1 segmented control, Review carrying how many lines need a look.
struct MeetingView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.runsMeetingWork) private var runsMeetingWork
    @Query(sort: \Member.sortOrder) private var members: [Member]
    @Bindable var meeting: Meeting

    @State private var tab: Tab = .review
    @State private var stage: ProcessingStage = .preparingModels
    @State private var didPickTab = false
    @State private var renaming = false
    @State private var confirmingDelete = false

    /// `initialTab` opens a finished meeting on that tab instead of picking one (Review if lines need a check, else
    /// the write-up if there is one, else the transcript).
    init(meeting: Meeting, initialTab: Tab? = nil) {
        _meeting = Bindable(meeting)
        if let initialTab {
            _tab = State(initialValue: initialTab)
            _didPickTab = State(initialValue: true)
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case review = "Review", transcript = "Transcript", minutes = "Minutes"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            switch meeting.status {
            case .recording, .processing:
                processingView
            case .failed:
                failedView
            case .needsReview, .ready:
                VStack(spacing: 0) {
                    SKSegmented(selection: $tab, options: Tab.allCases.map(option))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    switch tab {
                    case .review: ReviewView(meeting: meeting, members: members, showAll: false)
                    case .transcript: ReviewView(meeting: meeting, members: members, showAll: true)
                    case .minutes: MinutesView(meeting: meeting, members: members)
                    }
                }
                .onAppear {
                    guard !didPickTab else { return }
                    didPickTab = true
                    tab = meeting.linesNeedingReview.isEmpty ? (meeting.minutes == nil ? .transcript : .minutes) : .review
                }
            }
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sk1Chassis()
        .navigationTitle(meeting.title)
        .inlineTitle()
        .toolbar {
            // Not while it's being processed: the transcript is about to be written into it.
            if meeting.status != .recording, meeting.status != .processing {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Rename…") { renaming = true }
                        Button("Delete meeting…", role: .destructive) { confirmingDelete = true }
                    } label: {
                        Label("Edit", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $renaming) {
            MeetingTitleSheet(title: meeting.title) { title in
                meeting.title = title
                try? context.save()
            }
        }
        .confirmationDialog("Delete \(meeting.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete meeting", role: .destructive) { delete() }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("The recording, the transcript and the \(meeting.kind.documentName.lowercased()) are removed from this device. This can't be undone.")
        }
    }

    /// Goes back to Home first, then deletes once this screen has gone, so nothing on it reads a deleted meeting.
    private func delete() {
        let meeting = meeting
        router.path = []
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            meeting.delete(from: context)
        }
    }

    private func option(_ tab: Tab) -> SKSegmented<Tab>.Option {
        switch tab {
        case .review:
            let count = meeting.linesNeedingReview.count
            return .init(tab, tab.rawValue, badge: count > 0 ? "\(count)" : nil)
        case .transcript:
            return .init(tab, tab.rawValue)
        case .minutes:
            return .init(tab, meeting.kind.documentName)
        }
    }

    // MARK: Processing

    private var processingView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            SKCaption("Making the transcript")
            processingLCD
            Text("A one-hour meeting takes a few minutes. Keep Minits open; it all happens on this device.")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(20)
        .task(id: meeting.id) {
            guard runsMeetingWork else { return }
            await process()
        }
    }

    private var processingLCD: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        let percent = Int((stage.fraction * 100).rounded())
        return SKLCD {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SKLamp(color: .teal, lit: true, glow: 4, size: 7, label: "Working", blinking: true)
                    Text("WORKING")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                    Spacer(minLength: 8)
                    Text("ON THIS DEVICE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .lineLimit(1)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    Text(stage.label.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(alignment: .bottom, spacing: 3) {
                        SKSevenSegment("\(percent)", digitHeight: 30, spacing: 4)
                            .shadow(color: ink.opacity(0.15), radius: 0, x: 1, y: 1)
                        Text("%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                }

                ProgressCells(fraction: stage.fraction)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Working: \(stage.label)"))
        .accessibilityValue(Text("\(percent) percent"))
    }

    private var failedView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            SKCaption("Making the transcript")
            SKWell {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        SKLamp(color: .danger, lit: true, label: "Error")
                        SKCaption("Something went wrong")
                    }
                    Text(meeting.errorMessage ?? "The recording couldn't be processed.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(sk1Hex: palette.ink))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The recording is still saved, so nothing is lost.")
                        .sk1Hint()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                meeting.status = .processing
                try? context.save()
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.sk1Key(.orange, size: .large))
            Spacer()
        }
        .padding(20)
    }

    private var palette: SK1.Palette { SK1.palette(for: scheme) }

    private func process() async {
        guard meeting.status == .processing || meeting.status == .recording else { return }
        guard MeetingProcessing.begin(meeting.id) else { return }
        defer { MeetingProcessing.end(meeting.id) }

        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
        #endif

        meeting.status = .processing
        let voices = members
            .filter { meeting.attendeeIDs.contains($0.id) }
            .compactMap { member in member.embedding.map { EnrolledVoice(id: member.id, name: member.name, embedding: $0) } }
        let url = meeting.audioURL

        do {
            let lines = try await VoiceEngine.shared.process(meetingAt: url, voices: voices) { newStage in
                Task { @MainActor in stage = newStage }
            }
            for old in meeting.lines { context.delete(old) }
            meeting.lines = lines.map { draft in
                let line = TranscriptLine(start: draft.start, end: draft.end, text: draft.text)
                line.speakerID = draft.speakerID
                line.speakerName = draft.speakerName
                line.alternateSpeakerID = draft.alternateSpeakerID
                line.confidence = draft.confidence
                line.needsReview = draft.needsReview
                line.reviewNote = draft.reviewNote
                return line
            }
            meeting.status = meeting.linesNeedingReview.isEmpty ? .ready : .needsReview
            UserDefaults.standard.set(true, forKey: "modelsReady")
        } catch {
            meeting.errorMessage = error.localizedDescription
            meeting.status = .failed
        }
        try? context.save()
    }
}

/// How far processing has got, as a row of LCD cells: the done ones in the LCD's ink, the rest faint as an unlit
/// seven-segment is.
private struct ProgressCells: View {
    let fraction: Double
    private let count = 24

    var body: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        let lit = Int((min(max(fraction, 0), 1) * Double(count)).rounded())
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < lit ? ink : ink.opacity(SK1.SevenSegment.unlitOpacity))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// Stops the same meeting from being processed twice if its screen appears again.
@MainActor
enum MeetingProcessing {
    private static var running: Set<UUID> = []
    static func begin(_ id: UUID) -> Bool { running.insert(id).inserted }
    static func end(_ id: UUID) { running.remove(id) }
}
