import SK1Tokens
import SK1UI
import SwiftData
import SwiftUI

/// Screen A5: everyone Minits knows, outside of any meeting. Edit a name or role, record or re-record a voice, forget a
/// voice, or remove someone for good. Opened from Home's People key.
///
/// SK-1 look: an LCD header (how many people and how many have a voice), the people as rows in one sunken tray (avatar,
/// name and role, a teal VOICE lamp or NO VOICE, and a ⋯ key with the actions), and a cream Add key.
struct PeopleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Member.sortOrder) private var members: [Member]

    @State private var adding = false
    @State private var pendingSample: Member?
    @State private var actions = MemberActionState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                Text("Everyone here can be picked at roll call. Use ⋯ next to a name to edit them, record their voice again, forget their voice or remove them.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                    SKCaption("People")
                    if members.isEmpty {
                        SKWell {
                            Text("No one yet. Add people here or at roll call.")
                                .sk1Hint()
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        SKWell {
                            VStack(spacing: 0) {
                                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                                    if index > 0 { SKGroove() }
                                    row(member, colorIndex: member.colorIndex ?? index)
                                }
                            }
                        }
                    }
                    Button {
                        adding = true
                    } label: {
                        Label("Add person", systemImage: "plus")
                    }
                    .buttonStyle(.sk1Key(.cream))
                }

                Label("Voices stay on this device", systemImage: "lock")
                    .sk1Hint()
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .sk1Chassis()
        .navigationTitle("People")
        .inlineTitle()
        .sheet(isPresented: $adding, onDismiss: {
            if let member = pendingSample {
                pendingSample = nil
                actions.sampling = member
            }
        }) {
            MemberSheet(kind: nil) { name, role, _ in
                let member = Member(name: name, role: role, sortOrder: (members.map(\.sortOrder).max() ?? 0) + 1)
                member.colorIndex = Member.nextColor(among: members)
                context.insert(member)
                try? context.save()
                pendingSample = member
            }
        }
        .memberActionSheets($actions, members: members, kind: nil)
    }

    private var header: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        let voices = members.filter(\.hasVoice).count
        return SKLCD {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("PEOPLE")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .lineLimit(1)
                    Text(members.isEmpty ? "NO ONE YET" : "\(voices) OF \(members.count) HAVE A VOICE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    SKSevenSegment(String(format: "%02d", members.count), digitHeight: 30, spacing: 4)
                        .shadow(color: ink.opacity(0.15), radius: 0, x: 1, y: 1)
                        .opacity(members.isEmpty ? 0.4 : 1)
                    Text("SAVED")
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
        .accessibilityLabel(Text("People, \(members.count) saved, \(voices) with a voice"))
    }

    private func row(_ member: Member, colorIndex: Int) -> some View {
        let p = SK1.palette(for: scheme)
        return HStack(spacing: 12) {
            Avatar(initials: member.initials, colorIndex: colorIndex, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(sk1Hex: p.ink))
                    .lineLimit(1)
                SKIndicator(member.hasVoice ? (member.role.isEmpty ? "Voice saved" : "Voice · \(member.role)")
                                            : (member.role.isEmpty ? "No voice" : "No voice · \(member.role)"),
                            isOn: member.hasVoice)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(member.name)\(member.role.isEmpty ? "" : ", \(member.role)"), \(member.hasVoice ? "voice saved" : "no voice")"))
            Spacer(minLength: 0)
            MemberMenu(member: member, state: $actions)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .contextMenu { MemberMenu.items(member, state: $actions) }
    }
}

/// Which person each of the people sheets is open for: editing, recording a voice, forgetting a voice, removing.
struct MemberActionState {
    var editing: Member?
    var sampling: Member?
    var forgetting: Member?
    var removing: Member?
}

/// The ⋯ key on a person's row, with everything you can do to them. The same items show on touch and hold.
struct MemberMenu: View {
    let member: Member
    @Binding var state: MemberActionState

    var body: some View {
        Menu {
            Self.items(member, state: $state)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
        }
        .menuStyle(.button)
        .buttonStyle(.sk1Key(.cream))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("More for \(member.name)"))
    }

    @ViewBuilder
    static func items(_ member: Member, state: Binding<MemberActionState>) -> some View {
        Button {
            state.wrappedValue.editing = member
        } label: {
            Label("Edit name and role…", systemImage: "pencil")
        }
        Button {
            state.wrappedValue.sampling = member
        } label: {
            Label(member.hasVoice ? "Re-record voice" : "Record voice", systemImage: "mic")
        }
        if member.hasVoice {
            Button {
                state.wrappedValue.forgetting = member
            } label: {
                Label("Forget voice…", systemImage: "waveform.slash")
            }
        }
        Divider()
        Button(role: .destructive) {
            state.wrappedValue.removing = member
        } label: {
            Label("Remove \(member.name)…", systemImage: "trash")
        }
    }
}

extension View {
    /// The sheets behind `MemberMenu`: edit, record a voice, and the questions before forgetting a voice or removing
    /// someone. `members` is everyone, so a new voice can be checked against the others'. `kind` is the meeting at
    /// roll call, nil on the People screen.
    func memberActionSheets(_ state: Binding<MemberActionState>, members: [Member], kind: MeetingKind?) -> some View {
        modifier(MemberActionSheets(state: state, members: members, kind: kind))
    }
}

private struct MemberActionSheets: ViewModifier {
    @Environment(\.modelContext) private var context
    @Binding var state: MemberActionState
    let members: [Member]
    let kind: MeetingKind?

    func body(content: Content) -> some View {
        content
            .sheet(item: $state.sampling) { member in
                VoiceSampleSheet(member: member, others: members.filter { $0.id != member.id }, kind: kind)
            }
            .sheet(item: $state.editing) { member in
                MemberSheet(member: member, kind: kind) { name, role, updatingTranscripts in
                    member.update(name: name, role: role, updatingTranscripts: updatingTranscripts, in: context)
                }
            }
            .confirmSheet(
                item: $state.forgetting,
                title: { "Forget \($0.name)'s voice?" },
                message: { "Minits will no longer recognise \($0.name). They stay on your list, and you can record their voice again any time. Past transcripts don't change." },
                confirmTitle: "Forget voice",
                confirmSymbol: "waveform.slash",
                cancelTitle: "Keep it"
            ) { member in
                member.forgetVoice(in: context)
            }
            .confirmSheet(
                item: $state.removing,
                title: { "Remove \($0.name)?" },
                message: { member in
                    "\(member.name) is taken off your list\(member.hasVoice ? " and their saved voice is deleted" : ""). Past transcripts keep their name. This can't be undone."
                },
                confirmTitle: "Remove",
                confirmSymbol: "trash",
                cancelTitle: "Keep them"
            ) { member in
                // Wait for the sheet to go, so nothing on it reads a deleted member.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    context.delete(member)
                    try? context.save()
                }
            }
    }
}
