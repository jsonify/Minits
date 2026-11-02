import SK1Tokens
import SK1UI
import SwiftUI

/// Splits a line two people spoke into two lines: tap the first word the second person says, check the two parts,
/// then **Split**. Both parts go to Review, each with the line's choices, so you pick who said which.
struct SplitLineSheet: View {
    let text: String
    let start: Double
    let end: Double
    let wordStarts: [Double]
    let onSplit: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    /// The first word of the second part.
    @State private var cut: Int?

    /// `cut` starts with a word already picked (the screenshot tests use it).
    init(text: String, start: Double, end: Double, wordStarts: [Double], cut: Int? = nil,
         onSplit: @escaping (Int) -> Void) {
        self.text = text
        self.start = start
        self.end = end
        self.wordStarts = wordStarts
        self.onSplit = onSplit
        _cut = State(initialValue: cut)
    }

    private var words: [String] { LineSplit.words(text) }

    private var halves: LineSplit.Halves? {
        cut.flatMap { LineSplit.halves(text: text, start: start, end: end, wordStarts: wordStarts, at: $0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tap the first word the next person says.")
                        .sk1Hint()
                        .fixedSize(horizontal: false, vertical: true)
                    SKWell {
                        FlowLayout(spacing: 6) {
                            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                                wordKey(word, at: index)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let halves {
                        part("First part", from: start, text: halves.firstText)
                        part("Second part", from: halves.time, text: halves.secondText)
                        Text(halves.isExact
                             ? "Both parts go to Review, where you pick who said each."
                             : "Both parts go to Review, where you pick who said each. This line is from before Minits kept word timings, so the second part's start time is estimated.")
                            .sk1Hint()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sk1Chassis()
            .navigationTitle("Split line")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") {
                        guard let cut else { return }
                        onSplit(cut)
                        dismiss()
                    }
                    .disabled(halves == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    /// One word. The first can't start the second part; from the chosen word on, the words are lit orange.
    private func wordKey(_ word: String, at index: Int) -> some View {
        let p = SK1.palette(for: scheme)
        let chosen = cut == index
        let inSecond = cut.map { index >= $0 } ?? false
        return Button { cut = index } label: {
            Text(word)
                .font(.system(size: 16, weight: chosen ? .bold : .regular))
                .foregroundStyle(Color(sk1Hex: inSecond ? SK1.orange : p.ink))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(sk1Hex: chosen ? SK1.orange : p.inkSoft).opacity(chosen ? 1 : 0.35),
                                lineWidth: chosen ? 2 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(index == 0)
        .accessibilityLabel(Text(word))
        .accessibilityHint(Text(index == 0 ? "The first word stays with the first part"
                                           : "Start the second part with this word"))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func part(_ title: String, from time: Double, text: String) -> some View {
        VStack(alignment: .leading, spacing: SK1.Metrics.captionToWell) {
            HStack {
                SKCaption(title)
                Spacer()
                SKChip(time.clock)
            }
            SKWell {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(sk1Hex: SK1.palette(for: scheme).ink))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
