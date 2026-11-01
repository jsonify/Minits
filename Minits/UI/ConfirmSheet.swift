import SK1Tokens
import SK1UI
import SwiftUI

/// A question that needs a yes before Minits goes on (end the meeting, remove a person, forget a voice), in the SK-1
/// look rather than a system alert: on the chassis, a caption, a sentence saying what will happen, an optional LCD
/// readout of what's at stake, then the confirming key over a cream key that backs out.
///
/// On iPhone it rises from the bottom, just as tall as it needs to be; on the Mac it's a sheet on the window.
struct ConfirmSheet: View {
    enum Tone {
        /// Charcoal with a red lamp, as the End key on the recording screen.
        case stop
        /// Charcoal, for removing or forgetting something.
        case destructive
    }

    let title: String
    let message: String
    var readout: String?
    let confirmTitle: String
    var confirmSymbol: String?
    var tone: Tone = .destructive
    let cancelTitle: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SKCaption(title)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Color(sk1Hex: SK1.palette(for: scheme).ink))
                .fixedSize(horizontal: false, vertical: true)
            if let readout {
                SKReadout(readout)
            }
            VStack(spacing: 10) {
                Button {
                    dismiss()
                    onConfirm()
                } label: {
                    HStack(spacing: 8) {
                        if tone == .stop {
                            SKLamp(color: .red, lit: true, glow: 3, size: 6)
                        }
                        if let confirmSymbol {
                            Label(confirmTitle, systemImage: confirmSymbol)
                        } else {
                            Text(confirmTitle)
                        }
                    }
                }
                .buttonStyle(.sk1Key(.charcoal, size: .large))
                Button(cancelTitle) { dismiss() }
                    .buttonStyle(.sk1Key(.cream, size: .large))
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Asks `title` in a `ConfirmSheet` while `isPresented` is true; `onConfirm` runs once the user confirms.
    func confirmSheet(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        readout: String? = nil,
        confirmTitle: String,
        confirmSymbol: String? = nil,
        tone: ConfirmSheet.Tone = .destructive,
        cancelTitle: String,
        onConfirm: @escaping () -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            FittedSheet {
                ConfirmSheet(title: title, message: message, readout: readout, confirmTitle: confirmTitle,
                             confirmSymbol: confirmSymbol, tone: tone, cancelTitle: cancelTitle, onConfirm: onConfirm)
            }
        }
    }

    /// As `confirmSheet(isPresented:…)`, for an item: the sheet shows while `item` isn't nil and hands it to the text
    /// and to `onConfirm`.
    func confirmSheet<Item: Identifiable>(
        item: Binding<Item?>,
        title: @escaping (Item) -> String,
        message: @escaping (Item) -> String,
        confirmTitle: String,
        confirmSymbol: String? = nil,
        cancelTitle: String,
        onConfirm: @escaping (Item) -> Void
    ) -> some View {
        sheet(item: item) { value in
            FittedSheet {
                ConfirmSheet(title: title(value), message: message(value), confirmTitle: confirmTitle,
                             confirmSymbol: confirmSymbol, cancelTitle: cancelTitle) { onConfirm(value) }
            }
        }
    }
}

/// Puts a sheet's content on the chassis and, on iPhone, makes the sheet just as tall as the content.
private struct FittedSheet<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 320

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { height = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, new in height = new }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .sk1Chassis()
            #if os(iOS)
            .presentationDetents([.height(height + 24)])  // room for the home indicator
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            #else
            .frame(width: 400)
            #endif
    }
}
