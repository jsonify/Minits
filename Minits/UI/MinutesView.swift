import SK1Tokens
import SK1UI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Screen A4: the drafted minutes (board meeting) or summary (ad-hoc meeting), editable and shareable.
///
/// SK-1 look: before a draft, what will happen, any lines still to check (amber lamp) and the orange key that drafts
/// it, with an LCD readout while it works. After, a teal DRAFT lamp and a Redraft key, the text in a sunken tray, and
/// the Copy, PDF and orange Share keys.
struct MinutesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Bindable var meeting: Meeting
    let members: [Member]

    @State private var working = false
    @State private var progressText = ""
    @State private var errorText: String?
    @State private var confirmingRedo = false
    #if os(macOS)
    @State private var savingPDF = false
    #endif

    var body: some View {
        Group {
            if meeting.minutes == nil {
                startView
            } else {
                editorView
            }
        }
    }

    private var palette: SK1.Palette { SK1.palette(for: scheme) }

    private var startView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SKCaption(meeting.kind == .board ? "Draft the minutes" : "Write a summary")
                Text(MinutesWriter.aiAvailable ? aiDescription : MinutesWriter.aiUnavailableReason)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(sk1Hex: palette.ink))
                    .fixedSize(horizontal: false, vertical: true)
                if !meeting.linesNeedingReview.isEmpty {
                    note(.warning, "To check",
                         "\(meeting.linesNeedingReview.count) lines still need a speaker check. You can draft now and fix names later.")
                }
                if let errorText {
                    note(.danger, "Error", errorText)
                }
                if working {
                    SKReadout(progressText.isEmpty ? "WORKING…" : progressText.uppercased())
                }
                Button {
                    Task { await draft() }
                } label: {
                    Text(MinutesWriter.aiAvailable ? (meeting.kind == .board ? "Draft the minutes" : "Write the summary") : "Make an outline")
                }
                .buttonStyle(.sk1Key(.orange, size: .large))
                .disabled(working)
            }
            .padding(20)
        }
    }

    /// A lamp and caption with a sentence under them.
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

    private var aiDescription: String {
        switch meeting.kind {
        case .board:
            return "Apple Intelligence will read the transcript on this device and write formal minutes: attendance, motions with who moved and seconded, votes, and action items. You can edit everything after."
        case .adHoc:
            return "Apple Intelligence will read the transcript on this device and write a summary: what was discussed, decisions, action items, and open questions. You can edit everything after."
        }
    }

    private var editorView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                SKLamp(color: .success, lit: true, label: "Draft")
                SKCaption("Draft · edit anything")
                Spacer()
                Button("Redraft") { confirmingRedo = true }
                    .buttonStyle(.sk1Key(.cream))
                    .disabled(working)
            }

            if let errorText {
                note(.danger, "Error", errorText)
            }

            SKWell {
                TextEditor(text: Binding(
                    get: { meeting.minutes ?? "" },
                    set: { meeting.minutes = $0 }))
                    .font(.system(size: 16))
                    .foregroundStyle(Color(sk1Hex: palette.ink))
                    .tint(Color(sk1Hex: palette.ink))
                    .scrollContentBackground(.hidden)
                    .padding(10)
            }

            if working {
                SKReadout(progressText.isEmpty ? "WORKING…" : progressText.uppercased())
            }

            HStack(spacing: 10) {
                Button {
                    copy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.sk1Key(.cream, size: .large))
                pdfKey
                ShareLink(item: meeting.minutes ?? "", subject: Text(meeting.title)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.sk1Key(.orange, size: .large))
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

    /// The minutes or summary as a printable PDF named after the meeting.
    private var pdf: MinutesPDF { MinutesPDF(meeting: meeting, members: members) }

    /// iPhone: the share sheet with the PDF file. Mac: a save panel.
    @ViewBuilder private var pdfKey: some View {
        #if os(iOS)
        let file = pdf
        ShareLink(item: file, preview: SharePreview(file.fileName)) {
            Label("PDF", systemImage: "doc.richtext")
        }
        .buttonStyle(.sk1Key(.cream, size: .large))
        #else
        Button {
            savingPDF = true
        } label: {
            Label("PDF", systemImage: "doc.richtext")
        }
        .buttonStyle(.sk1Key(.cream, size: .large))
        .fileExporter(isPresented: $savingPDF, item: pdf, contentTypes: [.pdf],
                      defaultFilename: pdf.baseName) { result in
            if case .failure(let error) = result {
                errorText = "Couldn't save the PDF: \(error.localizedDescription)"
            }
        }
        #endif
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
