import SK1Tokens
import SK1UI
import SwiftData
import SwiftUI

/// Screen A1: pick the kind of meeting, learn each member's voice, pick who's here, start the meeting.
///
/// SK-1 look: the kind as a segmented control, an LCD header (how many are here and how many voices are saved), the
/// members as rows in one sunken tray (tap a row to mark them here or not; a teal lamp for a saved voice or a Record
/// key), the meeting name in an LCD text field, and the orange Start meeting key at the bottom.
struct RollCallView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Member.sortOrder) private var members: [Member]

    @State private var absent: Set<UUID> = []
    @State private var actions = MemberActionState()
    @State private var addingMember = false
    @State private var pendingSample: Member?
    @State private var micDenied = false
    @AppStorage("lastMeetingKind") private var kind: MeetingKind = .board
    @State private var meetingTitle = ""
    /// The title follows the meeting kind until the user types their own.
    @State private var titleEdited = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    SKSegmented(selection: $kind, options: MeetingKind.allCases.map { SKSegmented<MeetingKind>.Option($0, $0.label) },
                                caption: "Kind")
                    Text(kind == .board
                         ? "Formal minutes afterwards: attendance, motions, votes, action items."
                         : "A summary afterwards: what was discussed, decisions, action items.")
                        .sk1Hint()
                        .fixedSize(horizontal: false, vertical: true)
                }

                header

                Text(kind == .board
                     ? "Pass the phone, or tap Record next to a name. Each member says their name and role in one sentence so Minits learns their voice. Voices are saved for next time."
                     : "Optional. Record a voice for anyone you want named in the transcript; everyone else shows up as Guest 1, Guest 2… Voices are saved for next time.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)

                memberTray

                VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                    SKCaption("Meeting name")
                    SKTextField("Meeting name", text: Binding(
                        get: { meetingTitle },
                        set: { meetingTitle = $0; titleEdited = true }))
                }

                if micDenied {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        SKLamp(color: .danger, lit: true, label: "Error")
                        Text("Minits can't use the microphone. Turn it on in Settings › Privacy › Microphone.")
                            .sk1Hint()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .sk1Chassis()
        .onAppear { applyDefaults(for: kind) }
        .onChange(of: kind) { _, kind in applyDefaults(for: kind) }
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle("Step 1 of 2")
        .inlineTitle()
        .sheet(isPresented: $addingMember, onDismiss: {
            // Go straight to recording the new member's voice once the add sheet is gone.
            if let member = pendingSample {
                pendingSample = nil
                actions.sampling = member
            }
        }) {
            MemberSheet(kind: kind) { name, role, _ in
                let member = Member(name: name, role: role, sortOrder: (members.map(\.sortOrder).max() ?? 0) + 1)
                member.colorIndex = Member.nextColor(among: members)
                context.insert(member)
                try? context.save()
                pendingSample = member
            }
        }
        .memberActionSheets($actions, members: members, kind: kind)
    }

    private var palette: SK1.Palette { SK1.palette(for: scheme) }

    private var present: [Member] { members.filter { !absent.contains($0.id) } }

    private var presentWithVoice: [Member] { present.filter(\.hasVoice) }

    // MARK: - Header

    private var header: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        let voices = presentWithVoice.count
        return SKLCD {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("ROLL CALL")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .lineLimit(1)
                    Text(members.isEmpty ? "NO MEMBERS YET" : "\(voices) OF \(present.count) HERE HAVE A VOICE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    SKSevenSegment(String(format: "%02d", present.count), digitHeight: 30, spacing: 4)
                        .shadow(color: ink.opacity(0.15), radius: 0, x: 1, y: 1)
                        .opacity(present.isEmpty ? 0.4 : 1)
                    Text("HERE")
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
        .accessibilityLabel(Text("Roll call, \(present.count) here, \(voices) with a saved voice"))
    }

    // MARK: - Members

    private var memberTray: some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            SKCaption(kind == .board ? "Members" : "People")
            if !members.isEmpty {
                SKWell {
                    VStack(spacing: 0) {
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                            if index > 0 { SKGroove() }
                            MemberRow(
                                member: member,
                                colorIndex: member.colorIndex ?? index,
                                isHere: !absent.contains(member.id),
                                toggleHere: { toggle(member) },
                                record: { actions.sampling = member },
                                actions: $actions)
                            .contextMenu { MemberMenu.items(member, state: $actions) }
                        }
                    }
                }
            }
            Button {
                addingMember = true
            } label: {
                Label(kind == .board ? "Add member or guest" : "Add person", systemImage: "plus")
            }
            .buttonStyle(.sk1Key(.cream))
            Text("Tap a name to mark them here or not. Use ⋯ to edit someone, re-record or forget their voice, or remove them.")
                .sk1Hint()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                Task { await startMeeting() }
            } label: {
                Label("Start meeting", systemImage: "record.circle")
            }
            .buttonStyle(.sk1Key(.orange, size: .large))
            if presentWithVoice.isEmpty, kind == .board {
                Text("You can start without voice samples, but everyone will show up as Guest 1, Guest 2…")
                    .sk1Hint()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("Voices and audio stay on this device", systemImage: "lock")
                .sk1Hint()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Color(sk1Hex: palette.chassis)
                SKGroove()
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Board meetings start with every member here; ad-hoc meetings start with nobody, so saved
    /// board voices aren't matched against whoever happens to be in the room.
    private func applyDefaults(for kind: MeetingKind) {
        absent = kind == .board ? [] : Set(members.map(\.id))
        if !titleEdited { meetingTitle = Self.defaultTitle(for: kind) }
    }

    private func toggle(_ member: Member) {
        if absent.contains(member.id) { absent.remove(member.id) } else { absent.insert(member.id) }
    }

    private func startMeeting() async {
        guard await AudioRecorder.requestPermission() else {
            micDenied = true
            return
        }
        let title = meetingTitle.trimmingCharacters(in: .whitespaces)
        let meeting = Meeting(
            title: title.isEmpty ? Self.defaultTitle(for: kind) : title,
            kind: kind,
            attendeeIDs: members.filter { !absent.contains($0.id) }.map(\.id))
        context.insert(meeting)
        try? context.save()
        router.path.append(.recording(meeting))
    }

    private static func defaultTitle(for kind: MeetingKind) -> String {
        switch kind {
        case .board: return "\(Date().formatted(.dateTime.month(.wide))) Board Meeting"
        case .adHoc: return "Meeting, \(Date().formatted(.dateTime.month(.abbreviated).day()))"
        }
    }
}

private struct MemberRow: View {
    let member: Member
    let colorIndex: Int
    let isHere: Bool
    let toggleHere: () -> Void
    let record: () -> Void
    @Binding var actions: MemberActionState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = SK1.palette(for: scheme)
        HStack(spacing: 12) {
            Button(action: toggleHere) {
                HStack(spacing: 12) {
                    Avatar(initials: member.initials, colorIndex: colorIndex, size: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(member.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(sk1Hex: p.ink))
                            .lineLimit(1)
                        SKIndicator(isHere ? (member.role.isEmpty ? "Here" : "Here · \(member.role)") : "Not here today",
                                    isOn: isHere)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(member.name)\(member.role.isEmpty ? "" : ", \(member.role)"), \(isHere ? "here" : "not here")"))
            .accessibilityHint(Text("Toggles whether they're at this meeting"))

            if member.hasVoice {
                HStack(spacing: 6) {
                    SKLamp(color: .success, lit: true, glow: 3, size: 7)
                    Text("Voice")
                        .font(.sk1(SK1.TypeScale.indicator))
                        .tracking(SK1.TypeScale.indicator.kern)
                        .textCase(.uppercase)
                        .foregroundStyle(Color(sk1Hex: p.ink))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Voice saved"))
            } else {
                Button(action: record) {
                    Label("Record", systemImage: "mic.fill")
                }
                .buttonStyle(.sk1Key(.cream))
                .accessibilityLabel(Text("Record \(member.name)'s voice"))
            }

            MemberMenu(member: member, state: $actions)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .opacity(isHere ? 1 : 0.5)
    }
}

/// Adds a member or guest, or edits one: a name and an optional role, each in an LCD text field. Editing keeps the
/// voice; when the name changes, an opt-in toggle also renames them in transcripts already made.
///
/// The role field follows the meeting: a board meeting asks for a role (Chair, Treasurer…), an ad-hoc meeting for an
/// optional note (Mom, Coach…), and the People screen (`kind` nil) for either.
struct MemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var role: String
    @State private var updatingTranscripts = false
    private let member: Member?
    private let kind: MeetingKind?
    /// The name, the role and whether to rename them in past transcripts.
    private let onSave: (String, String, Bool) -> Void

    /// `member` nil adds someone new.
    init(member: Member? = nil, kind: MeetingKind? = .board, onSave: @escaping (String, String, Bool) -> Void) {
        self.member = member
        self.kind = kind
        self.onSave = onSave
        _name = State(initialValue: member?.name ?? "")
        _role = State(initialValue: member?.role ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var renamed: Bool { member.map { trimmedName != $0.name && !trimmedName.isEmpty } ?? false }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                    SKCaption("Name")
                    SKTextField("Name", text: $name)
                        .onSubmit(save)
                }
                VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                    SKCaption(roleCopy.caption)
                    SKTextField(roleCopy.caption, text: $role, prompt: roleCopy.prompt)
                        .onSubmit(save)
                    Text(roleCopy.hint)
                        .sk1Hint()
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let member {
                    if renamed {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Rename in past transcripts", isOn: $updatingTranscripts)
                                .toggleStyle(.sk1Square)
                            Text(updatingTranscripts
                                 ? "Every line already marked as \(member.name) will say \(trimmedName). Minutes and summaries already written keep the old name until you redraft them."
                                 : "Past transcripts keep \(member.name). New meetings use \(trimmedName).")
                                .sk1Hint()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if member.hasVoice {
                        Text("Their saved voice stays as it is.")
                            .sk1Hint()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sk1Chassis()
            .navigationTitle(member == nil ? (kind == .board ? "Add member" : "Add person")
                                           : (kind == .board ? "Edit member" : "Edit person"))
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(member == nil ? "Add" : "Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 300)
        #endif
    }

    /// What the role field is called, its placeholder and the hint under it.
    private var roleCopy: (caption: String, prompt: String, hint: String) {
        switch kind {
        case .board:
            return ("Role", "Chair, Treasurer, Member…",
                    "Optional. It's used in the minutes and in the line each member reads.")
        case .adHoc:
            return ("Note", "Mom, Coach, Neighbor…",
                    "Optional. A few words to tell people apart, shown next to their name.")
        case nil:
            return ("Role or note", "Chair, Treasurer, Mom, Coach…",
                    "Optional. Board minutes use it as their role; anywhere else it's shown next to their name.")
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName, role.trimmingCharacters(in: .whitespaces), renamed && updatingTranscripts)
        dismiss()
    }
}
