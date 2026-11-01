import SK1Tokens
import SK1UI
import SwiftUI

/// The player under the Transcript tab: an LCD with a lamp (PLAYING, PAUSED, READY or NO RECORDING), who's speaking,
/// the time and the length, and a scrubber of LCD cells with a tick at each marked motion or moment; under it, keys to
/// skip back 15 seconds, play or pause (orange), skip forward 15 seconds, and step the speed through 1×, 1.5× and 2×.
struct TranscriptPlayerBar: View {
    let player: MeetingPlayer
    /// The meeting's saved length, shown until the recording has been opened.
    let savedDuration: Double
    let marks: [Double]
    let markName: String
    /// Who's speaking at the playhead, once something has been played or picked.
    let speaker: String?

    @Environment(\.colorScheme) private var scheme

    private var duration: Double { max(player.duration ?? savedDuration, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            lcd
            HStack(spacing: 8) {
                SKKeyTray {
                    Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
                        .buttonStyle(.sk1Key(.cream))
                        .accessibilityLabel(Text("Back 15 seconds"))
                    Button { player.toggle() } label: {
                        Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                            .frame(minWidth: 64)
                    }
                    .buttonStyle(.sk1Key(.orange))
                    Button { player.skip(by: 15) } label: { Image(systemName: "goforward.15") }
                        .buttonStyle(.sk1Key(.cream))
                        .accessibilityLabel(Text("Forward 15 seconds"))
                }
                Spacer(minLength: 0)
                SKKeyTray {
                    Button { player.cycleRate() } label: { Text(rateText) }
                        .buttonStyle(.sk1Key(.cream, isOn: player.rate != 1))
                        .accessibilityLabel(Text("Speed"))
                        .accessibilityValue(Text(rateText))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            Color(sk1Hex: SK1.palette(for: scheme).chassis)
                .overlay(alignment: .top) { SKGroove() }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: LCD

    private var lcd: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        return SKLCD {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    SKLamp(color: player.failed ? .danger : .teal, lit: player.isPlaying || player.failed,
                           glow: 4, size: 7, label: statusText)
                    Text(statusText)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let speaker, !player.failed {
                        Text("· \(speaker.uppercased())")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("\(player.currentTime.clock) / \(duration.clock)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(2)
                }
                PlaybackScrubber(time: player.currentTime, duration: duration, marks: marks, markName: markName) { time in
                    player.seek(to: time)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var statusText: String {
        if player.failed { return "NO RECORDING" }
        if player.isPlaying { return "PLAYING" }
        return player.hasStarted ? "PAUSED" : "READY"
    }

    private var rateText: String {
        switch player.rate {
        case 1: return "1×"
        case 2: return "2×"
        default: return String(format: "%.1f×", player.rate)
        }
    }
}

/// Where playback is, as a row of LCD cells (played ones in the LCD's ink, the rest faint, as an unlit seven-segment
/// is), with a short tick above the cells at each mark. Drag or tap along it to move; VoiceOver swipes up or down to
/// skip 15 seconds.
private struct PlaybackScrubber: View {
    let time: Double
    let duration: Double
    let marks: [Double]
    let markName: String
    let seek: (Double) -> Void

    /// Where the finger is while dragging; nil otherwise.
    @State private var dragFraction: Double?
    private let count = 40

    private var fraction: Double {
        if let dragFraction { return dragFraction }
        guard duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }

    var body: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        let lit = Int((fraction * Double(count)).rounded())
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            ZStack(alignment: .topLeading) {
                ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in
                    if duration > 0 {
                        Rectangle()
                            .fill(ink)
                            .frame(width: 2, height: 4)
                            .offset(x: min(max(mark / duration, 0), 1) * (width - 2))
                    }
                }
                HStack(spacing: 2) {
                    ForEach(0..<count, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(index < lit ? ink : ink.opacity(SK1.SevenSegment.unlitOpacity))
                    }
                }
                .frame(height: 10)
                .offset(y: 6)
            }
            .frame(width: width, height: 16, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in dragFraction = min(max(value.location.x / width, 0), 1) }
                    .onEnded { value in
                        let picked = min(max(value.location.x / width, 0), 1)
                        dragFraction = nil
                        seek(picked * duration)
                    })
        }
        .frame(height: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Position"))
        .accessibilityValue(Text("\(SK1.Format.spokenDuration(time)) of \(SK1.Format.spokenDuration(duration))"
                                 + (marks.isEmpty ? "" : ", \(marks.count) \(markName)\(marks.count == 1 ? "" : "s") marked")))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seek(time + 15)
            case .decrement: seek(time - 15)
            @unknown default: break
            }
        }
    }
}
