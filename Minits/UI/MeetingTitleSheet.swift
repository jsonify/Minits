import SK1Tokens
import SK1UI
import SwiftUI

/// Renames a meeting: its name in an LCD text field. Used from Home's context menu and the meeting screen's Edit menu.
struct MeetingTitleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    private let onSave: (String) -> Void

    init(title: String, onSave: @escaping (String) -> Void) {
        _title = State(initialValue: title)
        self.onSave = onSave
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
                SKCaption("Meeting name")
                SKTextField("Meeting name", text: $title)
                    .onSubmit(save)
                Text("Shown on Home, in the transcript you share, and at the top of the minutes or summary when you next redraft.")
                    .sk1Hint()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sk1Chassis()
            .navigationTitle("Rename meeting")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmed.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 220)
        #endif
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
        dismiss()
    }
}
