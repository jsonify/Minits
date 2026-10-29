import SwiftData
import SwiftUI

/// Screen A3 ("Check who said what") and the full transcript, which share the same line cards.
struct ReviewView: View {
    @Environment(\.modelContext) private var context
    @Bindable var meeting: Meeting
    let members: [Member]
    let showAll: Bool

    @State private var player = ClipPlayer()
    @State private var motionsOnly = false
    @State private var namingGuest: TranscriptLine?
    @State private var guestName = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                intro
                ForEach(visibleLines) { line in
                    LineCard(
                        line: line,
                        members: members,
                        expanded: line.needsReview && !showAll,
                        isPlaying: player.playingLineID == line.id,
                        play: { player.toggle(lineID: line.id, url: meeting.audioURL, from: line.start, to: line.end) },
                        choose: { member in assign(line, to: member) },
                        confirm: { confirm(line) },
                        nameGuest: {
                            guestName = ""
                            namingGuest = line
                        })
                }
            }
            .padding(20)
        }
        .onDisappear { player.stop() }
        .alert("Who is \(namingGuest?.speakerName ?? "this")?", isPresented: Binding(
            get: { namingGuest != nil }, set: { if !$0 { namingGuest = nil } }
        )) {
            TextField("Name", text: $guestName)
            Button("Cancel", role: .cancel) { namingGuest = nil }
            Button("Save") {
                if let line = namingGuest { renameGuest(line, to: guestName) }
                namingGuest = nil
            }
        } message: {
            Text("Every line from \(namingGuest?.speakerName ?? "this voice") will use the name.")
        }
    }

    // MARK: Header

    @ViewBuilder private var intro: some View {
        if showAll {
            HStack {
                Toggle("Motions only", isOn: $motionsOnly)
                    .toggleStyle(.button)
                    .disabled(meeting.motionMarks.isEmpty)
                Spacer()
                ShareLink(item: transcriptText, subject: Text(meeting.title)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .font(.system(size: 14, weight: .semibold))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(meeting.linesNeedingReview.isEmpty ? "All checked" : "Check who said what")
                    .font(Theme.heading(28))
                Text(meeting.linesNeedingReview.isEmpty
                     ? "Every line has a speaker. Head to Minutes when you're ready."
                     : "\(meeting.durationSeconds.clock) · \(meeting.lines.count) lines. Minits wasn't sure about \(meeting.linesNeedingReview.count). Tap play to listen, then pick who it was.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryInk)
            }
            .padding(.bottom, 4)
        }
    }

    private var visibleLines: [TranscriptLine] {
        if !showAll { return meeting.linesNeedingReview }
        let lines = meeting.sortedLines
        guard motionsOnly else { return lines }
        return lines.filter { line in meeting.motionMarks.contains { line.end >= $0 - 30 && line.start <= $0 + 90 } }
    }

    private var transcriptText: String {
        var text = "\(meeting.title)\n\(meeting.startedAt.formatted(date: .long, time: .shortened))\n\n"
        for line in meeting.sortedLines {
            text += "[\(line.start.clock)] \(line.speakerName): \(line.text)\n\n"
        }
        return text
    }

    // MARK: Changes

    private func assign(_ line: TranscriptLine, to member: Member) {
        line.speakerID = member.id
        line.speakerName = member.name
        confirm(line)
    }

    private func confirm(_ line: TranscriptLine) {
        line.needsReview = false
        line.reviewNote = nil
        refreshStatus()
    }

    private func renameGuest(_ line: TranscriptLine, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let oldName = line.speakerName
        let oldID = line.speakerID
        // A guest's name applies to every line in their voice; a member line only changes itself.
        let targets = oldID == nil
            ? meeting.lines.filter { $0.speakerID == nil && $0.speakerName == oldName }
            : [line]
        if let member = members.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            for other in targets {
                other.speakerID = member.id
                other.speakerName = member.name
                other.needsReview = false
                other.reviewNote = nil
            }
        } else {
            for other in targets {
                other.speakerID = nil
                other.speakerName = trimmed
                other.needsReview = false
                other.reviewNote = nil
            }
        }
        refreshStatus()
    }

    private func refreshStatus() {
        meeting.status = meeting.linesNeedingReview.isEmpty ? .ready : .needsReview
        try? context.save()
    }
}

private struct LineCard: View {
    let line: TranscriptLine
    let members: [Member]
    let expanded: Bool
    let isPlaying: Bool
    let play: () -> Void
    let choose: (Member) -> Void
    let confirm: () -> Void
    let nameGuest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                if !expanded {
                    Avatar(initials: initials, colorIndex: colorIndex, size: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if expanded {
                        Text("\(line.reviewNote ?? "Unsure") · \(line.start.clock)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.warning)
                    } else {
                        speakerMenu {
                            HStack(spacing: 4) {
                                Text(line.speakerName).font(.system(size: 13, weight: .bold))
                                Text("· \(line.start.clock)").font(.system(size: 13)).foregroundStyle(Theme.secondaryInk)
                                if line.needsReview {
                                    Image(systemName: "questionmark.circle.fill").foregroundStyle(Theme.warningBorder)
                                }
                            }
                            .foregroundStyle(Theme.ink)
                        }
                    }
                }
                Spacer()
                Button(action: play) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 14))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(Theme.border))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(isPlaying ? "Stop" : "Play this line")
            }

            Text(line.text)
                .font(.system(size: 16))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)

            if expanded { choices }
        }
        .card(highlighted: expanded ? Theme.warningBorder : nil)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who said this?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryInk)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                if let current = member(line.speakerID) {
                    choiceButton("\(current.name) ✓", selected: true) { confirm() }
                } else {
                    choiceButton("Name \(line.speakerName)…", selected: true) { nameGuest() }
                }
                if let alternate = member(line.alternateSpeakerID), alternate.id != line.speakerID {
                    choiceButton(alternate.name, selected: false) { choose(alternate) }
                }
                speakerMenu {
                    Text("Someone else…")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                }
            }
        }
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(selected ? Theme.accentSoft : Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func speakerMenu<MenuLabel: View>(@ViewBuilder label: () -> MenuLabel) -> some View {
        Menu {
            ForEach(members) { member in
                Button(member.name) { choose(member) }
            }
            Divider()
            Button(line.speakerID == nil ? "Name \(line.speakerName)…" : "Someone not listed…") { nameGuest() }
            if line.needsReview {
                Button("Keep \(line.speakerName)") { confirm() }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private func member(_ id: UUID?) -> Member? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }

    private var colorIndex: Int? {
        guard let id = line.speakerID else { return nil }
        return members.firstIndex { $0.id == id }
    }

    private var initials: String {
        let parts = line.speakerName.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined().uppercased()
        return letters.isEmpty ? "?" : letters
    }
}
