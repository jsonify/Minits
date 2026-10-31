import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Screen A4: the drafted minutes (board meeting) or summary (ad-hoc meeting), editable and shareable.
struct MinutesView: View {
    @Environment(\.modelContext) private var context
    @Bindable var meeting: Meeting
    let members: [Member]

    @State private var working = false
    @State private var progressText = ""
    @State private var errorText: String?
    @State private var confirmingRedo = false

    var body: some View {
        Group {
            if meeting.minutes == nil {
                startView
            } else {
                editorView
            }
        }
    }

    private var startView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(meeting.kind == .board ? "Draft the minutes" : "Write a summary")
                    .font(Theme.heading(28))
                Text(MinutesWriter.aiAvailable ? aiDescription : MinutesWriter.aiUnavailableReason)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryInk)
                if !meeting.linesNeedingReview.isEmpty {
                    Label("\(meeting.linesNeedingReview.count) lines still need a speaker check. You can draft now and fix names later.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.warning)
                }
                if let errorText {
                    Text(errorText).font(.system(size: 14)).foregroundStyle(Theme.danger)
                }
                Button {
                    Task { await draft() }
                } label: {
                    if working {
                        HStack(spacing: 8) { ProgressView().tint(.white); Text(progressText.isEmpty ? "Working…" : progressText) }
                    } else {
                        Text(MinutesWriter.aiAvailable ? (meeting.kind == .board ? "Draft the minutes" : "Write the summary") : "Make an outline")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working)
            }
            .padding(20)
        }
    }

    private var aiDescription: String {
        switch meeting.kind {
        case .board:
            return "Apple Intelligence will read the transcript on this device and write formal minutes: attendance, motions with who moved and seconded, votes, and action items. You can edit everything after."
        case .adHoc:
            return "Apple Intelligence will read the transcript on this device and write a summary: what was discussed, decisions, action items, and open questions. You can edit everything after."
        }
    }

    private var editorView: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Draft · edit anything")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.success)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.successSoft, in: Capsule())
                Spacer()
                Button("Redraft") { confirmingRedo = true }
                    .font(.system(size: 14, weight: .semibold))
                    .disabled(working)
            }

            TextEditor(text: Binding(
                get: { meeting.minutes ?? "" },
                set: { meeting.minutes = $0 }))
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.hairline))

            if working {
                HStack(spacing: 8) { ProgressView(); Text(progressText) }
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryInk)
            }

            HStack(spacing: 10) {
                Button("Copy") { copy() }
                    .buttonStyle(SecondaryButtonStyle())
                ShareLink(item: meeting.minutes ?? "", subject: Text(meeting.title)) {
                    Text("Share")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .onDisappear { try? context.save() }
        .confirmationDialog("Write a new draft?", isPresented: $confirmingRedo, titleVisibility: .visible) {
            Button("Replace my edits with a new draft", role: .destructive) { Task { await draft() } }
            Button("Keep this draft", role: .cancel) {}
        } message: {
            Text("Useful after fixing speaker names. Any edits you made here will be replaced.")
        }
    }

    private func draft() async {
        working = true
        errorText = nil
        progressText = ""
        let byID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        let input = MinutesInput(
            kind: meeting.kind,
            title: meeting.title,
            date: meeting.startedAt,
            duration: meeting.durationSeconds,
            attendees: meeting.attendeeIDs.compactMap { byID[$0] }.map { (name: $0.name, role: $0.role) },
            lines: meeting.sortedLines.map { .init(time: $0.start, speaker: $0.speakerName, text: $0.text) },
            motionMarks: meeting.motionMarks)
        do {
            let text = try await MinutesWriter.draft(input) { message in
                Task { @MainActor in progressText = message }
            }
            meeting.minutes = text
            try? context.save()
        } catch {
            errorText = "Couldn't write the draft: \(error.localizedDescription). Here's an outline instead."
            meeting.minutes = MinutesWriter.outline(input)
        }
        working = false
    }

    private func copy() {
        #if os(iOS)
        UIPasteboard.general.string = meeting.minutes
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(meeting.minutes ?? "", forType: .string)
        #endif
    }
}
