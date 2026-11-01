import SK1Tokens
import SK1UI
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Color {
    /// The SK-1 ink, following Dark Mode: the app's tint, so system controls (alerts, menus, the caret) match.
    static let sk1Ink = Color(light: SK1.light.ink, dark: SK1.dark.ink)

    /// A colour that follows Dark Mode: `light` or `dark` (0xRRGGBB, sRGB), at `opacity`. For colours that must
    /// change with the appearance outside a view that reads `colorScheme` (the app's tint, avatars).
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

/// A member's initials in a coloured circle, so each speaker is easy to spot in roll call and the transcript. SK-1
/// has no colours for people, so these are Minits' own: light fills with dark text in light mode, muted dark fills
/// with the SK-1 ink in Dark Mode (each 7.5:1 or better). A guest (`colorIndex` nil) is grey-blue.
struct Avatar: View {
    let initials: String
    var colorIndex: Int?
    var size: CGFloat = 40

    var body: some View {
        let colors = colorIndex.map { Self.colors[$0 % Self.colors.count] } ?? Self.guest
        Text(initials)
            .font(.system(size: size * 0.37, weight: .bold))
            .foregroundStyle(colors.ink)
            .frame(width: size, height: size)
            .background(colors.fill, in: Circle())
            .accessibilityHidden(true)
    }

    private static let colors: [(fill: Color, ink: Color)] = hexes.map { lightFill, lightInk, darkFill in
        (Color(light: lightFill, dark: darkFill), Color(light: lightInk, dark: SK1.dark.ink))
    }
    /// Light fill, light-mode ink, Dark Mode fill.
    private static let hexes: [(UInt32, UInt32, UInt32)] = [
        (0xDCE8F5, 0x1F4E79, 0x243E54),
        (0xFCE6D4, 0x8A3E0B, 0x5F3518),
        (0xE4DDF5, 0x4B2E83, 0x3D2C5A),
        (0xDDF0E4, 0x1E6B3A, 0x244E31),
        (0xF8DDE6, 0x8C1D46, 0x602338),
        (0xDDF0F2, 0x0E5A63, 0x1B4448),
        (0xF3EBCF, 0x6B4E00, 0x4E3E12),
    ]
    private static let guest = (fill: Color(light: 0xE6ECF2, dark: SK1.dark.keyTop),
                                ink: Color(light: 0x4A5868, dark: SK1.dark.ink))
}

/// How far something has got (processing a meeting, the model download), as a row of LCD cells: the done ones in the LCD's ink, the rest faint as an unlit
/// seven-segment is.
struct ProgressCells: View {
    let fraction: Double
    var count = 24

    var body: some View {
        let ink = Color(sk1Hex: SK1.lcdInk)
        let lit = Int((min(max(fraction, 0), 1) * Double(count)).rounded())
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < lit ? ink : ink.opacity(SK1.SevenSegment.unlitOpacity))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// Whether screens start their work when they appear: recording on the recording screen, processing on the
    /// meeting screen. The screenshot tests turn it off, so they show each screen without the mic or the models.
    @Entry var runsMeetingWork = true
}

extension View {
    /// An inline title on iPhone; plain on Mac.
    func inlineTitle() -> some View {
        #if os(iOS)
        return self.navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }
}
