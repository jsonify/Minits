import SwiftUI

/// Option A: clean and familiar. Navy accent, serif headings, soft gray ground.
enum Theme {
    static let ground = Color(hex: 0xF5F7FA)
    static let card = Color.white
    static let ink = Color(hex: 0x15202B)
    static let secondaryInk = Color(hex: 0x4A5868)
    static let hairline = Color(hex: 0xE1E6EC)
    static let border = Color(hex: 0xC9D3DE)
    static let accent = Color(hex: 0x1F4E79)
    static let accentSoft = Color(hex: 0xEAF1F8)
    /// Darker end of the accent gradient behind the home screen's start panel.
    static let accentDeep = Color(hex: 0x14365A)
    /// Secondary text on an accent background.
    static let onAccentSecondary = Color(hex: 0xC9DAEA)
    static let success = Color(hex: 0x1E6B3A)
    static let successSoft = Color(hex: 0xE3F2E8)
    static let danger = Color(hex: 0xB42318)
    static let dangerSoft = Color(hex: 0xFDE8E7)
    static let motion = Color(hex: 0x6B4E00)
    static let motionSoft = Color(hex: 0xFFF4D6)
    static let warning = Color(hex: 0x8A5300)
    static let warningBorder = Color(hex: 0xC77700)

    /// Background/foreground pairs for member avatars, chosen so each pair stays readable.
    static let avatarColors: [(Color, Color)] = [
        (Color(hex: 0xDCE8F5), Color(hex: 0x1F4E79)),
        (Color(hex: 0xFCE6D4), Color(hex: 0x8A3E0B)),
        (Color(hex: 0xE4DDF5), Color(hex: 0x4B2E83)),
        (Color(hex: 0xDDF0E4), Color(hex: 0x1E6B3A)),
        (Color(hex: 0xF8DDE6), Color(hex: 0x8C1D46)),
        (Color(hex: 0xDDF0F2), Color(hex: 0x0E5A63)),
        (Color(hex: 0xF3EBCF), Color(hex: 0x6B4E00)),
    ]
    static let guestColors = (Color(hex: 0xE6ECF2), Color(hex: 0x4A5868))

    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Shared pieces

struct Avatar: View {
    let initials: String
    var colorIndex: Int?
    var size: CGFloat = 40

    var body: some View {
        let colors = colorIndex.map { Theme.avatarColors[$0 % Theme.avatarColors.count] } ?? Theme.guestColors
        Text(initials)
            .font(.system(size: size * 0.37, weight: .bold))
            .foregroundStyle(colors.1)
            .frame(width: size, height: size)
            .background(colors.0, in: Circle())
            .accessibilityHidden(true)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(tint.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.card.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }
}

struct CardBackground: ViewModifier {
    var highlighted: Color?

    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(highlighted ?? Theme.hairline, lineWidth: highlighted == nil ? 1 : 2))
    }
}

extension View {
    func card(highlighted: Color? = nil) -> some View { modifier(CardBackground(highlighted: highlighted)) }

    /// Large title style on iPhone; plain on Mac.
    func inlineTitle() -> some View {
        #if os(iOS)
        return self.navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }
}

/// Live level bars, used for voice samples and the recording screen.
struct LevelBars: View {
    let levels: [Float]
    var color: Color = Theme.accent
    var height: CGFloat = 36

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(level > 0.02 ? color : Theme.border)
                    .frame(width: 4, height: max(5, CGFloat(level) * height))
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.1), value: levels)
        .accessibilityHidden(true)
    }
}
