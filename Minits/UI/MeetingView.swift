import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// After the meeting: processing, then Review (A3), Transcript and Minutes or Summary (A4).
struct MeetingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Member.sortOrder) private var members: [Member]
    @Bindable var meeting: Meeting

    @State private var tab: Tab = .review
    @State private var stage: ProcessingStage = .preparingModels
    @State private var didPickTab = false

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
                    Picker("View", selection: $tab) {
                        ForEach(Tab.allCases) { tab in
                            if tab == .review, !meeting.linesNeedingReview.isEmpty {
                                Text("Review · \(meeting.linesNeedingReview.count)").tag(tab)
                            } else if tab == .minutes {
                                Text(meeting.kind.documentName).tag(tab)
                            } else {
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

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
        .background(Theme.ground)
        .navigationTitle(meeting.title)
        .inlineTitle()
    }

    // MARK: Processing

    private var processingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView(value: stage.fraction)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
            Text(stage.label)
                .font(Theme.heading(22))
                .multilineTextAlignment(.center)
            Text("A one-hour meeting takes a few minutes. Keep Minits open; it all happens on this device.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(28)
        .task(id: meeting.id) { await process() }
    }

    private var failedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Something went wrong")
                .font(Theme.heading(24))
            Text(meeting.errorMessage ?? "The recording couldn't be processed.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
            Button("Try again") {
                meeting.status = .processing
                try? context.save()
            }
            .buttonStyle(PrimaryButtonStyle())
            Text("The recording is still saved, so nothing is lost.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
            Spacer()
        }
        .padding(28)
    }

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

/// Stops the same meeting from being processed twice if its screen appears again.
@MainActor
enum MeetingProcessing {
    private static var running: Set<UUID> = []
    static func begin(_ id: UUID) -> Bool { running.insert(id).inserted }
    static func end(_ id: UUID) { running.remove(id) }
}
