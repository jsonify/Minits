import SK1Tokens
import SK1UI
import SwiftData
import SwiftUI

/// Screen A3 ("Check who said what") and the full transcript, which share the same line cards.
///
/// SK-1 look: Review opens with an LCD (how many lines are left to check, in seven-segment digits); the transcript
/// with a Motions only toggle and a Share key. Each line is a sunken tray: the speaker, the time on an LCD chip and a
/// play key; a flagged line has an amber lamp and the reason, and its choices are keys, the current guess lit.
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
            HStack(spacing: 12) {
                Toggle("Motions only", isOn: $motionsOnly)
                    .toggleStyle(.sk1Square)
                    .disabled(meeting.motionMarks.isEmpty)
                Spacer()
                ShareLink(item: transcriptText, subject: Text(meeting.title)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.sk1Key(.cream))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                reviewLCD
                Text(meeting.linesNeedingReview.isEmpty
                     ? "Every line has a speaker. Head to \(meeting.kind.documentName) when you're ready."
                     : "Minits wasn't sure who said these. Tap play to listen, then pick who it was.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 4)
        }
    }

    private var reviewLCD: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        let left = meeting.linesNeedingReview.count
        return SKLCD {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(left == 0 ? "ALL CHECKED" : "CHECK WHO SAID WHAT")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(meeting.durationSeconds.clock) · \(meeting.lines.count) LINES")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    SKSevenSegment(String(format: "%02d", left), digitHeight: 30, spacing: 4)
                        .shadow(color: ink.opacity(0.15), radius: 0, x: 1, y: 1)
                        .opacity(left == 0 ? 0.4 : 1)
                    Text("TO CHECK")
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
        .accessibilityLabel(Text(left == 0
            ? "All checked, \(meeting.lines.count) lines"
            : "\(left) of \(meeting.lines.count) lines to check"))
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
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = SK1.palette(for: scheme)
        SKWell {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    if expanded {
                        HStack(spacing: 6) {
                            SKLamp(color: .warning, lit: true, glow: 3, size: 7, label: "Needs a check")
                            SKCaption(line.reviewNote ?? "Unsure")
                        }
                    } else {
                        speakerMenu {
                            HStack(spacing: 8) {
                                Avatar(initials: initials, colorIndex: colorIndex, size: 28)
                                Text(line.speakerName)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color(sk1Hex: p.ink))
                                    .lineLimit(1)
                                if line.needsReview {
                                    SKLamp(color: .warning, lit: true, glow: 3, size: 7, label: "Needs a check")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Speaker: \(line.speakerName)\(line.needsReview ? ", needs a check" : "")"))
                        .accessibilityHint(Text("Change who said this"))
                    }
                    Spacer(minLength: 8)
                    SKChip(line.start.clock)
                        .accessibilityLabel(Text("At \(line.start.clock)"))
                    Button(action: play) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.sk1Key(isOn: isPlaying))
                    .accessibilityLabel(Text(isPlaying ? "Stop" : "Play this line"))
                }

                Text(line.text)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(sk1Hex: p.ink))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if expanded { choices }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 8) {
            SKCaption("Who said this?", tone: .soft)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                if let current = member(line.speakerID) {
                    choiceKey("\(current.name) ✓", isOn: true) { confirm() }
                        .accessibilityLabel(Text("Keep \(current.name)"))
                } else {
                    choiceKey("Name \(line.speakerName)…", isOn: true) { nameGuest() }
                }
                if let alternate = member(line.alternateSpeakerID), alternate.id != line.speakerID {
                    choiceKey(alternate.name, isOn: false) { choose(alternate) }
                }
                speakerMenu {
                    Text("Someone else…")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(.sk1Key(.cream, size: .large))
            }
        }
    }

    /// One answer as a key; the current guess is lit with the orange bar.
    private func choiceKey(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .buttonStyle(.sk1Key(.cream, isOn: isOn, size: .large))
    }

    /// The members to pick from, a way to name someone else, and (on a flagged line) keeping the guess. Give it a
    /// button style.
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
