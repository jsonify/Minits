import SwiftData
import SwiftUI

/// Screen A1: pick the kind of meeting, learn each member's voice, pick who's here, start the meeting.
struct RollCallView: View {
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Member.sortOrder) private var members: [Member]

    @State private var absent: Set<UUID> = []
    @State private var sampling: Member?
    @State private var addingMember = false
    @State private var pendingSample: Member?
    @State private var micDenied = false
    @AppStorage("lastMeetingKind") private var kind: MeetingKind = .board
    @State private var meetingTitle = ""
    /// The title follows the meeting kind until the user types their own.
    @State private var titleEdited = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Kind of meeting", selection: $kind) {
                        ForEach(MeetingKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(kind == .board
                         ? "Formal minutes afterwards: attendance, motions, votes, action items."
                         : "A summary afterwards: what was discussed, decisions, action items.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryInk)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Voice roll call")
                        .font(Theme.heading(32))
                    Text(kind == .board
                         ? "Pass the phone, or tap Record next to a name. Each member says their name and role in one sentence so Minits learns their voice. Voices are saved for next time."
                         : "Optional. Record a voice for anyone you want named in the transcript; everyone else shows up as Guest 1, Guest 2… Voices are saved for next time.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryInk)
                }

                VStack(spacing: 10) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                        MemberRow(
                            member: member,
                            colorIndex: index,
                            isHere: !absent.contains(member.id),
                            toggleHere: { toggle(member) },
                            record: { sampling = member })
                        .contextMenu {
                            Button("Re-record voice") { sampling = member }
                            Button("Remove member", role: .destructive) { remove(member) }
                        }
                    }

                    Button {
                        addingMember = true
                    } label: {
                        Label("Add member or guest", systemImage: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Meeting name")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.secondaryInk)
                    TextField("Meeting name", text: Binding(
                        get: { meetingTitle },
                        set: { meetingTitle = $0; titleEdited = true }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .card()
                }

                if micDenied {
                    Text("Minits can't use the microphone. Turn it on in Settings › Privacy › Microphone.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.danger)
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ground)
        .onAppear { applyDefaults(for: kind) }
        .onChange(of: kind) { _, kind in applyDefaults(for: kind) }
        .safeAreaInset(edge: .bottom) { footer }
        .navigationTitle("Step 1 of 2")
        .inlineTitle()
        .sheet(item: $sampling) { member in
            VoiceSampleSheet(member: member, others: members.filter { $0.id != member.id })
        }
        .sheet(isPresented: $addingMember, onDismiss: {
            // Go straight to recording the new member's voice once the add sheet is gone.
            if let member = pendingSample {
                pendingSample = nil
                sampling = member
            }
        }) {
            AddMemberSheet { name, role in
                let member = Member(name: name, role: role, sortOrder: (members.map(\.sortOrder).max() ?? 0) + 1)
                context.insert(member)
                try? context.save()
                pendingSample = member
            }
        }
    }

    private var presentWithVoice: [Member] {
        members.filter { $0.hasVoice && !absent.contains($0.id) }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Label("Voices and audio stay on this device", systemImage: "lock")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryInk)
            Button("Start meeting") {
                Task { await startMeeting() }
            }
            .buttonStyle(PrimaryButtonStyle())
            if presentWithVoice.isEmpty, kind == .board {
                Text("You can start without voice samples, but everyone will show up as Guest 1, Guest 2…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Theme.ground)
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

    private func remove(_ member: Member) {
        context.delete(member)
        try? context.save()
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

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggleHere) {
                HStack(spacing: 12) {
                    Avatar(initials: member.initials, colorIndex: colorIndex)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(isHere ? (member.role.isEmpty ? "Here" : member.role) : "Not here today")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(member.name), \(isHere ? "here" : "not here")")
            .accessibilityHint("Toggles whether they're at this meeting")

            if member.hasVoice {
                Label("Voice saved", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.success)
            } else {
                Button("Record", action: record)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .overlay(Capsule().stroke(Theme.accent))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
        }
        .card()
        .opacity(isHere ? 1 : 0.5)
    }
}

struct AddMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = ""
    let onAdd: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Role (Chair, Treasurer, Member…)", text: $role)
            }
            .navigationTitle("Add member")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(name.trimmingCharacters(in: .whitespaces), role.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 200)
        #endif
    }
}
