import SK1Tokens
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Temporary bridge to the SK-1 look (SK1Kit). The screens not yet moved to SK-1 (RollCall, Review, Minutes) still use
/// `Theme`, so every colour here maps to an SK-1 token and follows Dark Mode.
/// Status colours (danger, success, warning) keep the token's hue but are darkened in light mode and lightened in
/// Dark Mode until text in them reads at 4.5:1 or better on the chassis, a card and their own soft tint.
/// Orange is not used: in SK-1 it means "on" or the main action, so `accent` is the ink.
///
/// Remove this file when the last screen moves to SK-1.
enum Theme {
    /// The chassis.
    static let ground = Color(light: SK1.light.chassis, dark: SK1.dark.chassis)
    /// A key's face: white-ish in light mode, the dark key's lower face in Dark Mode.
    static let card = Color(light: SK1.light.keyTop, dark: SK1.dark.keyBottom)
    static let ink = Color(light: SK1.light.ink, dark: SK1.dark.ink)
    static let secondaryInk = Color(light: SK1.light.inkSoft, dark: SK1.dark.inkSoft)
    static let hairline = Color(light: SK1.light.groove, dark: SK1.dark.groove)
    static let border = Color(light: SK1.light.keySkirt, dark: SK1.dark.toggleOff)
    static let accent = ink
    static let accentSoft = Color(light: SK1.light.ink, dark: SK1.dark.ink, opacity: softOpacity)
    /// What sits on an `accent` (or status-coloured) fill: the chassis colour.
    static let onAccent = ground
    /// `SK1.recRed`, for text.
    static let danger = Color(light: 0xA83023, dark: 0xEF9A91)
    static let dangerSoft = Color(light: 0xA83023, dark: 0xEF9A91, opacity: softOpacity)
    /// `SK1.teal`, for text.
    static let success = Color(light: 0x146858, dark: 0x6DC0B0)
    static let successSoft = Color(light: 0x146858, dark: 0x6DC0B0, opacity: softOpacity)
    /// `SK1.amber`, for text.
    static let warning = Color(light: 0x845000, dark: 0xC8AE87)
    static let warningBorder = Color(light: 0xC77700, dark: 0xD49A4A)
    static let motion = warning
    static let motionSoft = Color(light: 0x845000, dark: 0xC8AE87, opacity: softOpacity)

    private static let softOpacity = 0.12

    /// Background/foreground pairs for member avatars: light fills with dark text in light mode, muted dark fills
    /// with the ink in Dark Mode (each 7.5:1 or better).
    static let avatarColors: [(Color, Color)] = avatarHexes.map { lightFill, lightInk, darkFill in
        (Color(light: lightFill, dark: darkFill), Color(light: lightInk, dark: SK1.dark.ink))
    }
    /// Light fill, light-mode ink, Dark Mode fill.
    private static let avatarHexes: [(UInt32, UInt32, UInt32)] = [
        (0xDCE8F5, 0x1F4E79, 0x243E54),
        (0xFCE6D4, 0x8A3E0B, 0x5F3518),
        (0xE4DDF5, 0x4B2E83, 0x3D2C5A),
        (0xDDF0E4, 0x1E6B3A, 0x244E31),
        (0xF8DDE6, 0x8C1D46, 0x602338),
        (0xDDF0F2, 0x0E5A63, 0x1B4448),
        (0xF3EBCF, 0x6B4E00, 0x4E3E12),
    ]
    static let guestColors = (Color(light: 0xE6ECF2, dark: SK1.dark.keyTop), Color(light: 0x4A5868, dark: SK1.dark.ink))

    /// A heading in the system font (SK-1 has no serif type).
    static func heading(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// A colour that follows Dark Mode: `light` or `dark` (0xRRGGBB, sRGB), at `opacity`.
    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            Self.platformColor(traits.userInterfaceStyle == .dark ? dark : light, opacity: opacity)
        })
        #elseif os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return Self.platformColor(isDark ? dark : light, opacity: opacity)
        })
        #endif
    }

    #if os(iOS)
    private static func platformColor(_ hex: UInt32, opacity: Double) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: CGFloat(opacity))
    }
    #elseif os(macOS)
    private static func platformColor(_ hex: UInt32, opacity: Double) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: CGFloat(opacity))
    }
    #endif
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
            .foregroundStyle(Theme.onAccent)
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
