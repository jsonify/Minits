import Foundation

/// Playful words that rotate under the real step while Minits works, so a long step still looks alive. They're
/// flavour only: the step name above them always says what's actually happening.
enum WorkingWords {
    static let all: [String] = [
        "Percolating",
        "Discombobulating",
        "Recombobulating",
        "Bebopping",
        "Noodling",
        "Ruminating",
        "Mulling it over",
        "Untangling crosstalk",
        "Herding syllables",
        "Marinating",
        "Cogitating",
        "Pondering",
        "Simmering",
        "Wrangling words",
        "Connecting dots",
        "Tinkering",
        "Whirring",
        "Brewing",
        "Sifting",
        "Counting the ums",
        "Finagling",
        "Puzzling it out",
        "Doodling in the margins",
        "Shuffling notes",
        "Sharpening pencils",
        "Kerfuffling",
        "Smooshing",
        "Lollygagging (not really)",
    ]

    /// How long each word stays up.
    static let secondsPerWord: TimeInterval = 3

    /// The word to show `elapsed` seconds in, starting from `offset` in the list.
    static func word(at elapsed: TimeInterval, offset: Int = 0) -> String {
        let ticks = Int(max(elapsed, 0) / secondsPerWord)
        let count = all.count
        return all[((offset + ticks) % count + count) % count]
    }
}

/// The percentage the working readout shows. Real progress comes in steps, and some steps report nothing for a long
/// time (loading models, the final writing pass), so between updates the readout eases from the last real value toward
/// where the step ends, fast at first and slower as it gets close, never reaching it. It never goes backwards.
enum WorkingProgress {
    /// Where to show progress `since` seconds after the last real update `fraction`, easing toward `ceiling` with time
    /// constant `tau` seconds (about 63% of the way there after `tau`, 95% after three times that).
    static func shown(fraction: Double, ceiling: Double, since: TimeInterval, tau: TimeInterval) -> Double {
        let start = min(max(fraction, 0), 1)
        let end = max(start, min(ceiling, 1))
        guard tau > 0, since > 0 else { return start }
        // Stop a hair short of the ceiling so a step never looks finished before it is.
        let eased = 1 - exp(-since / tau)
        return start + (end - start) * eased * 0.98
    }
}

#if canImport(SwiftUI)
import SK1Tokens
import SK1UI
import SwiftUI

/// The LCD shown while Minits works on a meeting (the transcript) or a write-up (minutes or a summary).
///
/// SK-1 look: a blinking teal WORKING lamp and which step of how many, ON THIS DEVICE; the real step and the percentage
/// in seven-segment digits; a playful word that changes every few seconds and the elapsed time; and a bar of LCD cells.
/// The percentage creeps toward the end of the step between real updates (`WorkingProgress`), so it never sits still.
struct WorkingLCD: View {
    let label: String
    let step: Int
    let stepCount: Int
    let fraction: Double
    let ceiling: Double
    /// How quickly the readout creeps toward `ceiling` between real updates; see `WorkingProgress.shown`.
    var tau: TimeInterval = 30

    @State private var started = Date()
    @State private var lastUpdate = Date()
    @State private var high = HighWater()
    @State private var wordOffset = Int.random(in: 0..<WorkingWords.all.count)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let now = context.date
            let shown = high.raise(to: WorkingProgress.shown(
                fraction: fraction, ceiling: ceiling, since: now.timeIntervalSince(lastUpdate), tau: tau))
            readout(shown: shown, elapsed: now.timeIntervalSince(started))
        }
        .onChange(of: fraction) { lastUpdate = .now }
        .onChange(of: label) { lastUpdate = .now }
    }

    private func readout(shown: Double, elapsed: TimeInterval) -> some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        let percent = Int((shown * 100).rounded(.down))
        return SKLCD {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    SKLamp(color: .teal, lit: true, glow: 4, size: 7, label: "Working", blinking: true)
                    Text(stepCount > 1 ? "WORKING · STEP \(step) OF \(stepCount)" : "WORKING")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Text("ON THIS DEVICE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .lineLimit(1)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    Text(label.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(alignment: .bottom, spacing: 3) {
                        SKSevenSegment("\(percent)", digitHeight: 30, spacing: 4)
                            .shadow(color: ink.opacity(0.15), radius: 0, x: 1, y: 1)
                        Text("%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                }

                HStack(spacing: 8) {
                    Text(WorkingWords.word(at: elapsed, offset: wordOffset).uppercased() + "…")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(0.75)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: Int(elapsed / WorkingWords.secondsPerWord))
                    Spacer(minLength: 8)
                    Text(SK1.Format.elapsed(elapsed))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .opacity(0.75)
                }

                ProgressCells(fraction: shown)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(stepCount > 1 ? "Working, step \(step) of \(stepCount): \(label)" : "Working: \(label)"))
        .accessibilityValue(Text("\(percent) percent, \(SK1.Format.spokenDuration(elapsed)) so far"))
    }
}

/// The highest percentage shown so far, so the readout never steps back when a real update lands below where the
/// creep had got to. A plain class: raising it while drawing must not redraw the view.
private final class HighWater {
    private var value = 0.0

    func raise(to candidate: Double) -> Double {
        value = max(value, candidate)
        return value
    }
}
#endif
