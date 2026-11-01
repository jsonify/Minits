import SK1Tokens
import SK1UI
import SwiftUI

/// The Transcript tab's cassette deck, after a 1970s front-loading deck in the SK-1 look: the meeting as a cassette
/// in a smoky window, its reels turning as it plays and the tape winding from one to the other; two backlit VU meters
/// between a VOLUME and a SPEED knob; and piano-key transport (STOP, rewind, PLAY, fast-forward, PAUSE) beside a tape
/// counter.
///
/// It's all drawn in code. The cassette and the meters are physical things, so they look the same in Light and Dark
/// Mode, apart from the meters' backlight dimming as the LCD's does. The rest follows the SK-1 palette.
struct CassetteDeck: View {
    let player: MeetingPlayer
    let title: String
    let date: Date

    @State private var volume = 10
    @State private var speed = DeckSpeed.normalIndex

    var body: some View {
        VStack(spacing: 8) {
            // The cassette between the knobs. The window is sized to the cassette, so it has no empty glass at its
            // sides: as tall as fits the width, up to 170 pt.
            ViewThatFits(in: .horizontal) {
                cassetteRow(height: 170)
                cassetteRow(height: 140)
                cassetteRow(height: 112)
            }

            HStack(spacing: 8) {
                VUMeter(level: player.levels.0, label: player.isStereo ? "LEFT" : "AVG")
                VUMeter(level: player.levels.1, label: player.isStereo ? "RIGHT" : "PEAK")
            }
            .frame(height: 56)

            HStack(alignment: .bottom, spacing: 8) {
                transport
                counter
            }
        }
        .onChange(of: volume, initial: true) { _, value in player.volume = Float(value) / 10 }
        .onChange(of: speed, initial: true) { _, index in player.rate = DeckSpeed.rates[index] }
    }

    /// VOLUME, the cassette window `height` tall, and SPEED, centred.
    private func cassetteRow(height: CGFloat) -> some View {
        HStack(spacing: 10) {
            DeckKnob(title: "Volume", position: $volume, scale: SK1.KnobScale(kind: .smooth(min: 0, max: 10, step: 1)),
                     endLabels: ("0", "10")) { "\($0)" }
            CassetteWindow(title: title, date: date, duration: player.duration, position: player.position,
                           playing: player.isPlaying)
                .frame(width: CassetteWindow.width(forHeight: height), height: height)
            DeckKnob(title: "Speed", position: $speed, scale: SK1.KnobScale(kind: .stops(count: DeckSpeed.rates.count)),
                     endLabels: ("¾", "2")) { DeckSpeed.label(DeckSpeed.rates[$0]) }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Transport

    private var transport: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                legend("Stop")
                legend("◀◀")
                legend("Play")
                legend("▶▶")
                legend("Pause")
            }
            .padding(.horizontal, 5)
            .accessibilityHidden(true)

            SKKeyTray(spacing: 3) {
                Button { player.stop() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.sk1Key(.cream, size: .large))
                    .accessibilityLabel(Text("Stop"))
                    .accessibilityHint(Text("Stops and rewinds to the start"))
                Button { player.skip(-10) } label: { Image(systemName: "backward.fill") }
                    .buttonStyle(.sk1Key(.cream, size: .large))
                    .accessibilityLabel(Text("Back 10 seconds"))
                Button { player.play() } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.sk1Key(.cream, isOn: player.state == .playing, size: .large))
                    .accessibilityLabel(Text("Play"))
                Button { player.skip(10) } label: { Image(systemName: "forward.fill") }
                    .buttonStyle(.sk1Key(.cream, size: .large))
                    .accessibilityLabel(Text("Forward 10 seconds"))
                Button { player.togglePause() } label: { Image(systemName: "pause.fill") }
                    .buttonStyle(.sk1Key(.cream, isOn: player.state == .paused, size: .large))
                    .accessibilityLabel(Text("Pause"))
                    .disabled(player.state == .stopped)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Color.sk1Ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }

    // MARK: Counter

    private var counter: some View {
        VStack(spacing: 4) {
            Text(player.failed ? "No tape" : "Counter")
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Color.sk1Ink)
                .accessibilityHidden(true)
            SKLCD {
                VStack(spacing: 3) {
                    SKSevenSegment(Self.counterText(player.position), digitHeight: 20, spacing: 3)
                    Text("/ \(player.duration.clock)")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(sk1Hex: SK1.lcdInk))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 63)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(player.failed ? "The recording couldn't be opened" : "Position"))
            .accessibilityValue(Text("\(player.position.clock) of \(player.duration.clock)"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// The counter: 12:05, or 1:02:05 past an hour.
    static func counterText(_ seconds: Double) -> String { seconds.clock }
}

/// The deck by itself on the chassis, as the screenshot tests show it mid-meeting.
struct CassetteDeckScreen: View {
    let player: MeetingPlayer
    let title: String
    let date: Date

    var body: some View {
        ScrollView {
            CassetteDeck(player: player, title: title, date: date)
                .padding(20)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
        }
        .sk1Chassis()
        .navigationTitle(title)
        .inlineTitle()
    }
}

/// The SPEED knob's clicks.
enum DeckSpeed {
    static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]
    static let normalIndex = 1

    static func label(_ rate: Float) -> String {
        let text = rate == rate.rounded() ? String(format: "%.0f", rate) : String(format: "%g", rate)
        return "\(text)×"
    }
}

// MARK: - The cassette

/// The tape in its window: a dark shell with a cream index label (the meeting's title and date on ruled lines, SIDE A
/// and a tape length), an orange band holding the tape window, two hubs and the brown tape packs. The packs move from
/// the left reel to the right as the meeting plays; while it plays, the reels turn at the speed a real tape's would.
/// Reduce Motion keeps them still.
struct CassetteWindow: View {
    let title: String
    let date: Date
    let duration: Double
    let position: Double
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let progress = duration > 0 ? min(max(position / duration, 0), 1) : 0
        let reels = TapeReels(progress: progress, duration: duration)
        let label = Self.label(title: title, date: date, duration: duration)
        let p = SK1.palette(for: scheme)
        Canvas { ctx, size in
            let bounds = CGRect(origin: .zero, size: size)
            Self.drawWindow(ctx, bounds, palette: p) { inside, inner in
                let cassette = Self.fit(in: inner.insetBy(dx: Self.margin, dy: Self.margin))
                Self.drawCassette(inside, cassette, label: label, reels: reels, spin: !reduceMotion)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cassette: \(title)"))
        .accessibilityValue(Text(playing ? "Playing, \(Int((progress * 100).rounded())) percent through"
                                         : "\(Int((progress * 100).rounded())) percent through"))
    }

    /// What's written on the index label.
    struct IndexLabel {
        let title: String
        let date: String
        let length: String
    }

    static func label(title: String, date: Date, duration: Double) -> IndexLabel {
        IndexLabel(title: title, date: date.formatted(date: .abbreviated, time: .omitted), length: tapeLength(duration))
    }

    /// The shortest common tape a meeting fits on one side of: C30, C60, C90 or C120.
    static func tapeLength(_ seconds: Double) -> String {
        let minutesPerSide = seconds / 60
        for c in [30, 60, 90] where minutesPerSide <= Double(c / 2) { return "C\(c)" }
        return "C120"
    }

    /// From the window's edge to the cassette: the 6 pt bezel, then the recess round the tape.
    static let bezel: CGFloat = 6
    static let margin: CGFloat = 8

    /// How wide the window is when it's `height` tall, so the cassette fills it with only the margin round it.
    static func width(forHeight height: CGFloat) -> CGFloat {
        let border = 2 * (bezel + margin)
        return (height - border) * aspect + border
    }

    static let aspect: CGFloat = 100.4 / 63.8

    /// A cassette's proportions (100.4 × 63.8 mm), as large as fits in `rect`, centred.
    static func fit(in rect: CGRect) -> CGRect {
        var w = rect.width, h = w / aspect
        if h > rect.height { h = rect.height; w = h * aspect }
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }

    // MARK: Drawing

    /// The recess in the chassis, with smoky glass drawn over whatever `content` draws inside it.
    static func drawWindow(_ ctx: GraphicsContext, _ rect: CGRect, palette p: SK1.Palette,
                           content: (GraphicsContext, CGRect) -> Void) {
        let outer = Path(roundedRect: rect.insetBy(dx: 0, dy: 0.5), cornerRadius: 12, style: .continuous)
        // The frame round the window: a raised cream bezel.
        ctx.fill(outer, with: .linearGradient(Gradient(colors: [Color(sk1Hex: p.keyTop), Color(sk1Hex: p.keyBottom)]),
                                              startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                              endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        ctx.stroke(outer, with: .color(.black.opacity(p.dark ? 0.5 : 0.18)), lineWidth: 0.5)

        // The recess.
        let inner = rect.insetBy(dx: bezel, dy: bezel)
        let recess = Path(roundedRect: inner, cornerRadius: 7, style: .continuous)
        ctx.fill(recess, with: .linearGradient(Gradient(colors: [Color(sk1Hex: 0x2a2926), Color(sk1Hex: 0x3a3833)]),
                                               startPoint: CGPoint(x: inner.midX, y: inner.minY),
                                               endPoint: CGPoint(x: inner.midX, y: inner.maxY)))
        var clipped = ctx
        clipped.clip(to: recess)
        content(clipped, inner)

        // Smoky glass: a faint tint, a sheen across the top left, and an inner shadow.
        clipped.fill(recess, with: .color(Color(sk1Hex: 0x6b5a3a, opacity: 0.10)))
        let sheen = Path { path in
            path.move(to: CGPoint(x: inner.minX, y: inner.minY))
            path.addLine(to: CGPoint(x: inner.minX + inner.width * 0.42, y: inner.minY))
            path.addLine(to: CGPoint(x: inner.minX + inner.width * 0.22, y: inner.maxY))
            path.addLine(to: CGPoint(x: inner.minX, y: inner.maxY))
            path.closeSubpath()
        }
        clipped.fill(sheen, with: .linearGradient(Gradient(colors: [.white.opacity(0.13), .white.opacity(0.02)]),
                                                  startPoint: CGPoint(x: inner.minX, y: inner.minY),
                                                  endPoint: CGPoint(x: inner.minX + inner.width * 0.4, y: inner.maxY)))
        var shadow = clipped
        shadow.addFilter(.shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 2))
        var ring = Path(inner.insetBy(dx: -20, dy: -20))
        ring.addPath(recess)
        shadow.fill(ring, with: .color(.black), style: FillStyle(eoFill: true))
    }

    static func drawCassette(_ ctx: GraphicsContext, _ r: CGRect, label: IndexLabel, reels: TapeReels, spin: Bool) {
        let w = r.width, h = r.height
        func x(_ f: CGFloat) -> CGFloat { r.minX + f * w }
        func y(_ f: CGFloat) -> CGFloat { r.minY + f * h }

        // The shell, casting a shadow on the recess.
        let shell = Path(roundedRect: r, cornerRadius: w * 0.035, style: .continuous)
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(0.5), radius: 3, x: 0, y: 2))
        shadowed.fill(shell, with: .color(Color(sk1Hex: 0x2f2d2a)))
        ctx.fill(shell, with: .linearGradient(Gradient(colors: [Color(sk1Hex: 0x3e3c38), Color(sk1Hex: 0x2a2826)]),
                                              startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        ctx.stroke(shell, with: .color(.white.opacity(0.08)), lineWidth: 0.6)

        // The five screws.
        for (fx, fy) in [(0.035, 0.06), (0.965, 0.06), (0.035, 0.94), (0.965, 0.94), (0.5, 0.84)] as [(CGFloat, CGFloat)] {
            let d = w * 0.022
            let screw = CGRect(x: x(fx) - d / 2, y: y(fy) - d / 2, width: d, height: d)
            ctx.fill(Path(ellipseIn: screw), with: .color(Color(sk1Hex: 0x8c8880)))
            var slot = Path()
            slot.move(to: CGPoint(x: screw.minX + d * 0.2, y: screw.midY))
            slot.addLine(to: CGPoint(x: screw.maxX - d * 0.2, y: screw.midY))
            ctx.stroke(slot, with: .color(Color(sk1Hex: 0x3a3833)), lineWidth: max(0.5, d * 0.15))
        }

        // The index label.
        let labelRect = CGRect(x: x(0.065), y: y(0.07), width: w * 0.87, height: h * 0.62)
        let labelPath = Path(roundedRect: labelRect, cornerRadius: w * 0.012, style: .continuous)
        ctx.fill(labelPath, with: .color(Color(sk1Hex: 0xf4efe2)))
        var onLabel = ctx
        onLabel.clip(to: labelPath)

        // Ruled lines for writing on.
        let ink = Color(sk1Hex: 0x2b2a27)
        let rule = Color(sk1Hex: 0xb9b2a2)
        let lineYs = [0.165, 0.265].map { y($0) }
        for ly in lineYs {
            var line = Path()
            line.move(to: CGPoint(x: labelRect.minX + w * 0.1, y: ly))
            line.addLine(to: CGPoint(x: labelRect.maxX - w * 0.03, y: ly))
            onLabel.stroke(line, with: .color(rule), lineWidth: 0.5)
        }
        let side = onLabel.resolve(Text("A").font(.system(size: h * 0.13, weight: .heavy)).foregroundColor(ink))
        onLabel.draw(side, at: CGPoint(x: labelRect.minX + w * 0.05, y: y(0.2)), anchor: .center)

        let hand = Font.custom("Marker Felt", size: h * 0.095)
        let titleText = onLabel.resolve(Text(label.title).font(hand).foregroundColor(Color(sk1Hex: 0x1f3a6b)))
        onLabel.draw(titleText, in: CGRect(x: labelRect.minX + w * 0.11, y: lineYs[0] - h * 0.13, width: labelRect.width - w * 0.15,
                                           height: h * 0.135))
        let dateText = onLabel.resolve(Text(label.date).font(.custom("Marker Felt", size: h * 0.07))
            .foregroundColor(Color(sk1Hex: 0x1f3a6b)))
        onLabel.draw(dateText, in: CGRect(x: labelRect.minX + w * 0.11, y: lineYs[1] - h * 0.1, width: labelRect.width - w * 0.15,
                                          height: h * 0.1))

        // The band across the middle, holding the tape window.
        let band = CGRect(x: labelRect.minX, y: y(0.345), width: labelRect.width, height: h * 0.3)
        onLabel.fill(Path(band), with: .linearGradient(Gradient(colors: [Color(sk1Hex: SK1.orangeTop), Color(sk1Hex: SK1.orangeBottom)]),
                                                        startPoint: CGPoint(x: band.midX, y: band.minY),
                                                        endPoint: CGPoint(x: band.midX, y: band.maxY)))
        let length = onLabel.resolve(Text(label.length).font(.system(size: h * 0.11, weight: .heavy)).foregroundColor(.white))
        onLabel.draw(length, at: CGPoint(x: band.maxX - w * 0.075, y: band.midY), anchor: .center)
        let sideText = onLabel.resolve(Text("SIDE A").font(.system(size: h * 0.045, weight: .bold)).foregroundColor(.white.opacity(0.9)))
        onLabel.draw(sideText, at: CGPoint(x: band.minX + w * 0.075, y: band.midY), anchor: .center)

        // The tape window, with the packs and hubs behind it.
        let windowRect = CGRect(x: x(0.24), y: y(0.38), width: w * 0.52, height: h * 0.23)
        let window = Path(roundedRect: windowRect, cornerRadius: h * 0.04, style: .continuous)
        ctx.fill(window, with: .color(Color(sk1Hex: 0x1d1b19)))
        var inWindow = ctx
        inWindow.clip(to: window)
        let hubRadius = w * 0.04
        let centers = [CGPoint(x: x(0.5 - 0.2), y: windowRect.midY), CGPoint(x: x(0.5 + 0.2), y: windowRect.midY)]
        let packs = [reels.supplyRadius, reels.takeUpRadius].map { CGFloat($0) * hubRadius }
        let angles = spin ? [reels.supplyAngle, reels.takeUpAngle] : [0, 0]
        for (index, center) in centers.enumerated() {
            let pr = packs[index]
            let pack = CGRect(x: center.x - pr, y: center.y - pr, width: 2 * pr, height: 2 * pr)
            inWindow.fill(Path(ellipseIn: pack), with: .radialGradient(
                Gradient(colors: [Color(sk1Hex: 0x4a3221), Color(sk1Hex: 0x6b4a32), Color(sk1Hex: 0x5a3c28)]),
                center: center, startRadius: hubRadius, endRadius: pr))
            drawHub(inWindow, center: center, radius: hubRadius, angle: angles[index])
        }
        // The tape between the packs, along the bottom of the window.
        var tape = Path()
        tape.move(to: CGPoint(x: centers[0].x, y: centers[0].y + packs[0]))
        tape.addLine(to: CGPoint(x: centers[1].x, y: centers[1].y + packs[1]))
        inWindow.stroke(tape, with: .color(Color(sk1Hex: 0x4a3221)), lineWidth: 1)
        // The window's glass.
        inWindow.fill(window, with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .white.opacity(0)]),
                                                    startPoint: CGPoint(x: windowRect.minX, y: windowRect.minY),
                                                    endPoint: CGPoint(x: windowRect.minX + windowRect.width * 0.3, y: windowRect.maxY)))
        ctx.stroke(window, with: .color(.black.opacity(0.4)), lineWidth: 0.8)

        // The trapezoid along the bottom, where the heads meet the tape.
        let trap = Path { path in
            path.move(to: CGPoint(x: x(0.17), y: y(0.76)))
            path.addLine(to: CGPoint(x: x(0.83), y: y(0.76)))
            path.addLine(to: CGPoint(x: x(0.87), y: r.maxY - 0.5))
            path.addLine(to: CGPoint(x: x(0.13), y: r.maxY - 0.5))
            path.closeSubpath()
        }
        ctx.fill(trap, with: .color(Color(sk1Hex: 0x34322f)))
        ctx.stroke(trap, with: .color(.white.opacity(0.07)), lineWidth: 0.6)
        for fx in [0.3, 0.7] as [CGFloat] {
            let d = w * 0.035
            ctx.fill(Path(ellipseIn: CGRect(x: x(fx) - d / 2, y: y(0.87) - d / 2, width: d, height: d)),
                     with: .color(Color(sk1Hex: 0x151413)))
        }
        for fx in [0.4, 0.6] as [CGFloat] {
            let s = w * 0.022
            ctx.fill(Path(CGRect(x: x(fx) - s / 2, y: y(0.89) - s / 2, width: s, height: s)), with: .color(Color(sk1Hex: 0x151413)))
        }
    }

    /// A white hub with six teeth, turned `angle` radians (clockwise as drawn).
    static func drawHub(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, angle: Double) {
        let hub = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
        ctx.fill(Path(ellipseIn: hub), with: .color(Color(sk1Hex: 0xf3f0ea)))
        ctx.stroke(Path(ellipseIn: hub), with: .color(.black.opacity(0.3)), lineWidth: 0.5)
        let hole = radius * 0.62
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - hole, y: center.y - hole, width: 2 * hole, height: 2 * hole)),
                 with: .color(Color(sk1Hex: 0x1d1b19)))
        var turned = ctx
        turned.translateBy(x: center.x, y: center.y)
        turned.rotate(by: .radians(angle))
        let toothWidth = radius * 0.22, toothLength = radius * 0.3
        for i in 0..<6 {
            var tooth = turned
            tooth.rotate(by: .degrees(Double(i) * 60))
            tooth.fill(Path(CGRect(x: -toothWidth / 2, y: -hole - 0.5, width: toothWidth, height: toothLength)),
                       with: .color(Color(sk1Hex: 0xf3f0ea)))
        }
    }
}

/// The tape packs and how far each reel has turned, worked out from where playback is.
///
/// The tape runs at a steady speed, so a reel turns faster the less tape is wound on it. Radii are in hub radii: the
/// hub is 1 and a full pack 2.4. The packs keep their total area as the tape moves across. Turning is chosen so a bare
/// hub would turn at 3 radians a second, whatever the meeting's length; at 2× speed the reels turn twice as fast.
struct TapeReels: Equatable {
    static let hub: Double = 1
    static let full: Double = 2.4
    /// The tape's speed, in hub radii a second.
    static let speed: Double = 3

    /// The left reel's pack (it gives tape) and the right's (it takes it up).
    let supplyRadius: Double
    let takeUpRadius: Double
    /// How far each reel has turned, in radians; negative is anticlockwise, as both reels turn on side A.
    let supplyAngle: Double
    let takeUpAngle: Double

    init(progress: Double, duration: Double) {
        let p = min(max(progress, 0), 1)
        let area = Self.full * Self.full - Self.hub * Self.hub
        supplyRadius = (Self.full * Self.full - p * area).squareRoot()
        takeUpRadius = (Self.hub * Self.hub + p * area).squareRoot()
        guard duration > 0 else {
            supplyAngle = 0
            takeUpAngle = 0
            return
        }
        // The integral of speed / radius over the time played.
        let k = Self.speed * 2 * duration / area
        supplyAngle = -(k * (Self.full - supplyRadius)).truncatingRemainder(dividingBy: 2 * .pi)
        takeUpAngle = -(k * (takeUpRadius - Self.hub)).truncatingRemainder(dividingBy: 2 * .pi)
    }
}

// MARK: - The VU meter

/// A backlit VU meter: a warm cream face in an olive surround, a scale from 20 to +3 with the red zone above 0, and a
/// needle at `level` (0 at rest to 1 at full scale). The backlight dims in Dark Mode as the LCD's glass does.
struct VUMeter: View {
    let level: Float
    let label: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let brightness = SK1.palette(for: scheme).lcdBrightness
        Canvas { ctx, size in
            Self.draw(ctx, CGRect(origin: .zero, size: size), level: CGFloat(level), label: label, brightness: brightness)
        }
        .frame(minWidth: 80, maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label == "AVG" ? "Average level" : label == "PEAK" ? "Peak level" : "\(label.capitalized) level"))
        .accessibilityValue(Text("\(Int((level * 100).rounded())) percent"))
    }

    /// The marked readings, and which carry numbers.
    private static let ticks: [Float] = [-20, -10, -7, -5, -3, -2, -1, 0, 1, 2, 3]
    private static let numbered: [Float] = [-20, -10, -5, -3, 0, 3]
    /// How far the needle swings either side of upright, in radians.
    private static let swing: CGFloat = 0.72

    static func draw(_ ctx: GraphicsContext, _ rect: CGRect, level: CGFloat, label: String, brightness: CGFloat) {
        // The olive surround.
        let outer = Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 6, style: .continuous)
        ctx.fill(outer, with: .linearGradient(Gradient(colors: [Color(sk1Hex: 0x858c6b, brightness: brightness),
                                                                Color(sk1Hex: 0x6a7154, brightness: brightness)]),
                                              startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                              endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        ctx.stroke(outer, with: .color(.black.opacity(0.35)), lineWidth: 0.5)

        // The face, lit from behind.
        let face = rect.insetBy(dx: 5, dy: 5)
        let facePath = Path(roundedRect: face, cornerRadius: 3, style: .continuous)
        ctx.fill(facePath, with: .linearGradient(Gradient(colors: [Color(sk1Hex: 0xfdf1d2, brightness: brightness),
                                                                   Color(sk1Hex: 0xefd59c, brightness: brightness)]),
                                                 startPoint: CGPoint(x: face.midX, y: face.minY),
                                                 endPoint: CGPoint(x: face.midX, y: face.maxY)))
        var lit = ctx
        lit.clip(to: facePath)
        lit.fill(Path(ellipseIn: CGRect(x: face.midX - face.width * 0.45, y: face.minY - face.height * 0.5,
                                        width: face.width * 0.9, height: face.height * 0.95)),
                 with: .radialGradient(Gradient(colors: [Color(sk1Hex: 0xfff6dc, opacity: 0.85 * brightness), .clear]),
                                       center: CGPoint(x: face.midX, y: face.minY), startRadius: 0, endRadius: face.width * 0.45))

        // The scale, an arc round a pivot below the face.
        let pivot = CGPoint(x: face.midX, y: face.maxY + face.height * 0.62)
        let radius = pivot.y - face.minY - face.height * 0.42
        func angle(_ fraction: CGFloat) -> CGFloat { -swing + 2 * swing * fraction }
        func point(_ fraction: CGFloat, _ r: CGFloat) -> CGPoint {
            let a = angle(fraction)
            return CGPoint(x: pivot.x + sin(a) * r, y: pivot.y - cos(a) * r)
        }
        let ink = Color(sk1Hex: 0x2b2a27)
        let red = Color(sk1Hex: SK1.recRed)
        let zero = CGFloat(VUScale.fraction(vu: 0))
        func arc(from a: CGFloat, to b: CGFloat) -> Path {
            Path { path in
                path.addArc(center: pivot, radius: radius, startAngle: .radians(Double(angle(a)) - .pi / 2),
                            endAngle: .radians(Double(angle(b)) - .pi / 2), clockwise: false)
            }
        }
        lit.stroke(arc(from: 0, to: zero), with: .color(ink), lineWidth: 0.8)
        lit.stroke(arc(from: zero, to: 1), with: .color(red), lineWidth: 2.4)

        let numberSize = max(6, min(8, face.height * 0.2))
        for vu in ticks {
            let f = CGFloat(VUScale.fraction(vu: vu))
            let color = vu > 0 ? red : ink
            var tick = Path()
            tick.move(to: point(f, radius))
            tick.addLine(to: point(f, radius + (numbered.contains(vu) ? 5 : 3)))
            lit.stroke(tick, with: .color(color), lineWidth: 0.8)
            if numbered.contains(vu) {
                let text = lit.resolve(Text(vu > 0 ? "+\(Int(vu))" : "\(Int(abs(vu)))")
                    .font(.system(size: numberSize, weight: .semibold)).foregroundColor(color))
                lit.draw(text, at: point(f, radius + 5 + numberSize * 0.75), anchor: .center)
            }
        }
        let vuText = lit.resolve(Text("VU").font(.system(size: numberSize + 1, weight: .bold)).foregroundColor(ink))
        lit.draw(vuText, at: CGPoint(x: face.midX, y: face.maxY - face.height * 0.3), anchor: .center)
        let labelText = lit.resolve(Text(label).font(.system(size: max(6, numberSize - 1), weight: .bold))
            .foregroundColor(ink.opacity(0.75)))
        lit.draw(labelText, at: CGPoint(x: face.minX + 4, y: face.maxY - 3), anchor: .bottomLeading)

        // The needle.
        let f = min(max(level, 0), 1)
        var needle = Path()
        needle.move(to: pivot)
        needle.addLine(to: point(f, radius + 6))
        var shadow = lit
        shadow.addFilter(.shadow(color: .black.opacity(0.25), radius: 1, x: 1, y: 1))
        shadow.stroke(needle, with: .color(Color(sk1Hex: 0x1a1918)), lineWidth: 1.1)

        // The cover over the needle's pivot.
        let cover = CGRect(x: face.midX - face.width * 0.14, y: face.maxY - face.height * 0.16, width: face.width * 0.28,
                           height: face.height * 0.16 + 1)
        lit.fill(Path(roundedRect: cover, cornerRadius: 2), with: .color(Color(sk1Hex: 0x3a3530)))

        // An inner shadow, so the face sits behind the surround.
        var inner = ctx
        inner.clip(to: facePath)
        inner.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: 1))
        var ring = Path(face.insetBy(dx: -10, dy: -10))
        ring.addPath(facePath)
        inner.fill(ring, with: .color(.black), style: FillStyle(eoFill: true))
    }
}

// MARK: - The knob

/// A knurled knob with printed ticks, using SK1Kit's knob arithmetic (`SK1.KnobScale`): drag up or down to turn it
/// and with VoiceOver swipe up or down. Its title sits under it, and its
/// value shows while it's being turned.
struct DeckKnob: View {
    let title: String
    @Binding var position: Int
    let scale: SK1.KnobScale
    var endLabels: (String, String)? = nil
    let valueLabel: (Int) -> String

    @State private var carry: CGFloat = 0
    @State private var lastY: CGFloat?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = SK1.palette(for: scheme)
        VStack(spacing: 1) {
            Canvas { ctx, size in
                draw(ctx, CGRect(origin: .zero, size: size), palette: p)
            }
            .frame(width: 44, height: 42)
            .contentShape(Circle())
            .gesture(drag)
            Text(lastY == nil ? title : valueLabel(position))
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.sk1Ink)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
        .frame(width: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(valueLabel(position)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: position = scale.clamp(position + 1)
            case .decrement: position = scale.clamp(position - 1)
            @unknown default: break
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let y = value.translation.height
                let moved = (lastY ?? 0) - y  // Up turns it up.
                lastY = y
                let steps = scale.steps(forDrag: moved, carry: &carry)
                if steps != 0 { position = scale.clamp(position + steps) }
            }
            .onEnded { _ in
                lastY = nil
                carry = 0
            }
    }

    private func draw(_ ctx: GraphicsContext, _ rect: CGRect, palette p: SK1.Palette) {
        let center = CGPoint(x: rect.midX, y: rect.midY + 1)
        let r = min(rect.width, rect.height) / 2 - 7
        func point(_ degrees: CGFloat, _ radius: CGFloat) -> CGPoint {
            let a = degrees * .pi / 180
            return CGPoint(x: center.x + cos(a) * radius, y: center.y - sin(a) * radius)
        }
        let ink = Color(sk1Hex: p.ink)

        // The printed ticks, the end ones longer.
        let ticks = scale.ticks
        for (i, f) in ticks.enumerated() {
            let a = SK1.KnobScale.startAngle - SK1.KnobScale.sweep * f
            let long = i == 0 || i == ticks.count - 1
            var tick = Path()
            tick.move(to: point(a, r + 2))
            tick.addLine(to: point(a, r + (long ? 6 : 4.5)))
            ctx.stroke(tick, with: .color(ink.opacity(0.8)), lineWidth: 0.8)
        }
        if let endLabels {
            for (text, a) in [(endLabels.0, SK1.KnobScale.startAngle), (endLabels.1, SK1.KnobScale.startAngle - SK1.KnobScale.sweep)] {
                let resolved = ctx.resolve(Text(text).font(.system(size: 6.5, weight: .bold)).foregroundColor(ink.opacity(0.8)))
                ctx.draw(resolved, at: point(a, r + 3).applying(.init(translationX: 0, y: 4)), anchor: .top)
            }
        }

        // The body, casting a shadow, its edge knurled.
        let body = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
        var shadowed = ctx
        shadowed.addFilter(.shadow(color: .black.opacity(p.dark ? 0.55 : 0.28), radius: 2, x: 0, y: 2))
        shadowed.fill(Path(ellipseIn: body), with: .color(Color(sk1Hex: p.keySkirt)))
        ctx.fill(Path(ellipseIn: body), with: .linearGradient(
            Gradient(colors: [Color(sk1Hex: p.keyTop), Color(sk1Hex: p.keySkirt)]),
            startPoint: CGPoint(x: body.minX, y: body.minY), endPoint: CGPoint(x: body.maxX, y: body.maxY)))
        var knurl = Path()
        for i in 0..<40 {
            let a = CGFloat(i) * 9
            knurl.move(to: point(a, r * 0.82))
            knurl.addLine(to: point(a, r - 0.4))
        }
        ctx.stroke(knurl, with: .color(.black.opacity(p.dark ? 0.35 : 0.16)), lineWidth: 0.6)
        ctx.stroke(Path(ellipseIn: body), with: .color(.black.opacity(0.25)), lineWidth: 0.5)

        // The cap, with a soft sheen.
        let capR = r * 0.74
        let cap = CGRect(x: center.x - capR, y: center.y - capR, width: 2 * capR, height: 2 * capR)
        ctx.fill(Path(ellipseIn: cap), with: .radialGradient(
            Gradient(colors: [Color(sk1Hex: p.keyTop), Color(sk1Hex: p.keyBottom)]),
            center: CGPoint(x: cap.midX - capR * 0.3, y: cap.midY - capR * 0.4), startRadius: 0, endRadius: capR * 1.4))
        ctx.stroke(Path(ellipseIn: cap), with: .color(.black.opacity(0.12)), lineWidth: 0.5)

        // The pointer.
        let a = scale.angle(position)
        var pointer = Path()
        pointer.move(to: point(a, capR * 0.3))
        pointer.addLine(to: point(a, capR * 0.92))
        ctx.stroke(pointer, with: .color(Color(sk1Hex: SK1.orange)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}
