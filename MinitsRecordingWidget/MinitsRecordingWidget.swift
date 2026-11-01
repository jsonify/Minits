import ActivityKit
import AppIntents
import SK1Tokens
import SwiftUI
import WidgetKit

/// The widget extension: only the recording's Live Activity.
@main
struct MinitsWidgets: WidgetBundle {
    var body: some Widget {
        RecordingActivityWidget()
    }
}

/// The recording on the lock screen and in the Dynamic Island, in the SK-1 look: an olive LCD with the red REC lamp
/// (PAUSED or INTERRUPTED when paused), the kind of meeting and how many are here, the elapsed time and the marks;
/// under it, Pause/Resume and the orange Mark key. Tapping anywhere else opens Minits on the recording.
struct RecordingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(hex: SK1.light.chassis))
                .activitySystemActionForegroundColor(Color(hex: SK1.light.ink))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusLabel(state: context.state)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: context.state)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Keys(attributes: context.attributes, state: context.state, dark: true)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Lamp(lit: !context.state.isPaused, size: 8)
            } compactTrailing: {
                ElapsedText(state: context.state)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(context.state.isPaused ? .white.opacity(0.6) : Color(hex: SK1.recRed))
                    .frame(maxWidth: 56)
            } minimal: {
                Lamp(lit: !context.state.isPaused, size: 8)
            }
            .keylineTint(Color(hex: SK1.recRed))
        }
    }
}

// MARK: - Lock screen

private struct LockScreenView: View {
    let attributes: RecordingActivityAttributes
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        let ink = Color(hex: SK1.lcdInk)
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Lamp(lit: !state.isPaused, size: 7)
                    Text(statusText)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                    Spacer(minLength: 8)
                    Text("\(attributes.kindName) · \(attributes.present) HERE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .lineLimit(1)
                }
                HStack(alignment: .lastTextBaseline) {
                    ElapsedText(state: state)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    Text(marksText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .lineLimit(1)
                }
                Text(attributes.title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                    .lineLimit(1)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Color(hex: SK1.glassTop), Color(hex: SK1.glassMiddle),
                                                  Color(hex: SK1.glassBottom)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: SK1.light.bezelBottom), lineWidth: 3))
            )

            Keys(attributes: attributes, state: state, dark: false)
        }
        .padding(14)
    }

    private var statusText: String {
        if state.wasInterrupted { return "INTERRUPTED" }
        return state.isPaused ? "PAUSED" : "REC"
    }

    private var marksText: String {
        let name = attributes.markName.uppercased()
        return "\(state.marks) \(name)\(state.marks == 1 ? "" : "S")"
    }
}

// MARK: - Parts

/// The red REC lamp: lit while recording, dim when paused.
private struct Lamp: View {
    let lit: Bool
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color(hex: SK1.recRed).opacity(lit ? 1 : SK1.lampDimmed))
            .frame(width: size, height: size)
            .shadow(color: Color(hex: SK1.recRed).opacity(lit ? 0.8 : 0), radius: 3)
            .accessibilityLabel(Text(lit ? "Recording" : "Paused"))
    }
}

private struct StatusLabel: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            Lamp(lit: !state.isPaused, size: 8)
            Text(state.wasInterrupted ? "INTERRUPTED" : state.isPaused ? "PAUSED" : "REC")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1)
                .foregroundStyle(.white)
        }
    }
}

/// The elapsed time: counting up while recording, held while paused.
private struct ElapsedText: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        if state.isPaused {
            Text(Self.clock(state.elapsed))
        } else {
            Text(timerInterval: state.timerStart...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(.trailing)
        }
    }

    /// 0:42, 41:02 or 1:03:12, as the app shows it.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// Pause/Resume (cream) and Mark (orange), as SK-1 keys.
private struct Keys: View {
    let attributes: RecordingActivityAttributes
    let state: RecordingActivityAttributes.ContentState
    /// In the Dynamic Island (black) rather than on the cream lock screen.
    let dark: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleRecordingPauseIntent()) {
                Label(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                    .modifier(KeyFace(top: dark ? SK1.dark.keyTop : SK1.light.keyTop,
                                      bottom: dark ? SK1.dark.keyBottom : SK1.light.keyBottom,
                                      ink: dark ? SK1.dark.keyInk : SK1.light.keyInk))
            }
            .buttonStyle(.plain)
            Button(intent: MarkRecordingIntent()) {
                Label("Mark \(attributes.markName.lowercased())", systemImage: "bookmark.fill")
                    .modifier(KeyFace(top: SK1.orangeTop, bottom: SK1.orangeBottom, ink: 0xffffff))
            }
            .buttonStyle(.plain)
        }
    }
}

/// A key's raised face: a gradient, rounded, with an upper-case tracked title.
private struct KeyFace: ViewModifier {
    let top: UInt32
    let bottom: UInt32
    let ink: UInt32

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(Color(hex: ink))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Color(hex: top), Color(hex: bottom)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1.5)
            )
    }
}

private extension Color {
    /// An SK-1 token (0xRRGGBB, sRGB).
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}
