import AppKit
import Observation
import SwiftUI

/// The preset the whole interface draws with: set by the app from Settings ›
/// Appearance › Colour (and the system accent for Match System), and by the
/// widgets from their payload. `Lagoon`'s colour tokens read it, so a view
/// that draws with them redraws in place when it changes.
@Observable
public final class LagoonTheme {
    public static let shared = LagoonTheme()

    public var palette: DataPalette = .lagoon

    private init() {}

    /// For the widgets: draw with the preset the app wrote into the payload,
    /// or Lagoon when it names none.
    public static func use(presetNamed name: String?) {
        let palette = name.flatMap(DataPalette.init(rawValue:)) ?? .lagoon
        if shared.palette != palette { shared.palette = palette }
    }
}

/// One preset's interface colours, each a Dark and a Light value.
public struct LagoonTokens {
    public let nsBackground: NSColor
    public let background: Color
    public let surface: Color
    public let surfaceRaised: Color
    public let stroke: Color
    public let strokeStrong: Color
    public let accent: Color
    public let accentDeep: Color
    public let accentGlow: Color
    public let accentMuted: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let powerIn: Color
    public let warning: Color
    public let critical: Color
    public let onAccent: Color
}

extension DataPalette {
    /// This preset's interface colours.
    public var tokens: LagoonTokens { Self.allTokens[self]! }

    /// Built once, like `colors`: each `themed` call makes a new dynamic
    /// colour that never compares equal to another.
    private static let allTokens: [DataPalette: LagoonTokens] =
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.buildTokens()) })

    private func buildTokens() -> LagoonTokens {
        let h = tokenHexes
        func color(_ pair: (dark: UInt32, light: UInt32)) -> Color { Lagoon.themed(pair.dark, pair.light) }
        let nsBackground = Lagoon.themedNS(h.background.dark, h.background.light)
        return LagoonTokens(
            nsBackground: nsBackground, background: Color(nsColor: nsBackground),
            surface: color(h.surface), surfaceRaised: color(h.surfaceRaised),
            stroke: Lagoon.themed(h.accent.dark, h.accent.light, opacity: 0.16, lightOpacity: 0.18),
            strokeStrong: Lagoon.themed(h.accent.dark, h.accent.light, opacity: 0.34, lightOpacity: 0.40),
            accent: color(h.accent), accentDeep: color(h.accentDeep), accentGlow: color(h.accentGlow),
            accentMuted: color(h.accentMuted), textPrimary: color(h.textPrimary),
            textSecondary: color(h.textSecondary), textTertiary: color(h.textTertiary),
            powerIn: color(h.powerIn), warning: color(h.warning), critical: color(h.critical),
            onAccent: color(h.onAccent))
    }

    /// (Dark, Light) pairs. Lagoon's are the app's own values. The others come
    /// from Lagoon's in OKLCH (docs/decisions.md, 2026-10-31):
    /// - accent, accentGlow and accentMuted are the preset's `colors`;
    ///   accentDeep is its accent scaled as Lagoon's deep is to its accent;
    /// - surfaces and text keep Lagoon's lightness and chroma at the preset's
    ///   hue (no chroma for Graphite), with Light text darkened where needed
    ///   to keep its contrast target;
    /// - powerIn, warning and critical keep their hue unless it lies within
    ///   30° of the preset's, in which case it moves to 30° away, so it stays
    ///   at least 27° away after rounding. Lagoon keeps its own values; its
    ///   closest pair, powerIn and accent, is 27.6° apart, which sets that floor;
    /// - onAccent is black or white, whichever reads better on both accents.
    private struct TokenHexes {
        var background, surface, surfaceRaised, accent, accentDeep, accentGlow, accentMuted: (dark: UInt32, light: UInt32)
        var textPrimary, textSecondary, textTertiary, powerIn, warning, critical, onAccent: (dark: UInt32, light: UInt32)
    }

    private var tokenHexes: TokenHexes {
        switch self {
        case .lagoon:
            TokenHexes(background: (0x000000, 0xF6FAF9), surface: (0x070D0E, 0xFFFFFF),
                       surfaceRaised: (0x0D1719, 0xE9F2F1), accent: (0x3EE6D4, 0x096D68),
                       accentDeep: (0x0FA3A0, 0x08635E), accentGlow: (0x8AFFF3, 0x0A8F86),
                       accentMuted: (0x1C5F5A, 0x5E9E97), textPrimary: (0xEAFBF8, 0x0B1F1D),
                       textSecondary: (0x9BBAB5, 0x3D5A56), textTertiary: (0x5E7B77, 0x4D6763),
                       powerIn: (0x7BF5B0, 0x166E3D), warning: (0xFFC266, 0x8F5300), critical: (0xFF6B7A, 0xB22436),
                       onAccent: (0x000000, 0xFFFFFF))
        case .sky:
            TokenHexes(background: (0x000000, 0xF7F9FC), surface: (0x0B0B10, 0xFFFFFF),
                       surfaceRaised: (0x14141C, 0xECF0F7), accent: (0x74ACFD, 0x075ABC),
                       accentDeep: (0x4E79B6, 0x0652AB), accentGlow: (0x9CC2F9, 0x0976F3),
                       accentMuted: (0x18519D, 0x6592D2), textPrimary: (0xF2F7FF, 0x141B27),
                       textSecondary: (0xA5B4C9, 0x485467), textTertiary: (0x687589, 0x566273),
                       powerIn: (0x7BF5B0, 0x166E3D), warning: (0xFFC266, 0x8D5200), critical: (0xFF6B7A, 0xB22436),
                       onAccent: (0x000000, 0xFFFFFF))
        case .iris:
            TokenHexes(background: (0x000000, 0xFAF8FB), surface: (0x0F0A0C, 0xFFFFFF),
                       surfaceRaised: (0x1B1216, 0xF4EEF3), accent: (0xFA78FE, 0x980B9D),
                       accentDeep: (0xB350B6, 0x8A098F), accentGlow: (0xF9A2FA, 0xC60FCC),
                       accentMuted: (0x821F85, 0xC663C9), textPrimary: (0xFEF3FD, 0x221721),
                       textSecondary: (0xBFABBE, 0x5E4D5E), textTertiary: (0x806D7E, 0x6B5B6A),
                       powerIn: (0x7BF5B0, 0x166E3D), warning: (0xFFC266, 0x8D5200), critical: (0xFF6B7A, 0xB22436),
                       onAccent: (0x000000, 0xFFFFFF))
        case .orchid:
            TokenHexes(background: (0x000000, 0xFCF8F9), surface: (0x100A0A, 0xFFFFFF),
                       surfaceRaised: (0x1C1212, 0xF6EDEF), accent: (0xFE82B5, 0xA90A63),
                       accentDeep: (0xB65980, 0x9A085A), accentGlow: (0xFAA8C7, 0xDC0E82),
                       accentMuted: (0x901E57, 0xD76394), textPrimary: (0xFFF3F7, 0x25161B),
                       textSecondary: (0xC6AAB3, 0x644C54), textTertiary: (0x856C74, 0x705A61),
                       powerIn: (0x7BF5B0, 0x146D3C), warning: (0xFFC266, 0x8B5100), critical: (0xFF6E67, 0xB22629),
                       onAccent: (0x000000, 0xFFFFFF))
        case .ember:
            TokenHexes(background: (0x000000, 0xFCF8F8), surface: (0x100A08, 0xFFFFFF),
                       surfaceRaised: (0x1B130F, 0xF6EEEC), accent: (0xFE8581, 0xB10B25),
                       accentDeep: (0xB65B58, 0xA10921), accentGlow: (0xF9AAA5, 0xE60F32),
                       accentMuted: (0x961F27, 0xD76B68), textPrimary: (0xFFF4F3, 0x261615),
                       textSecondary: (0xC8AAA8, 0x664C4A), textTertiary: (0x876D6A, 0x725A58),
                       powerIn: (0x7BF5B0, 0x166E3D), warning: (0xFFC266, 0x8D5200), critical: (0xF56CAC, 0xA9266C),
                       onAccent: (0x000000, 0xFFFFFF))
        case .tangerine:
            TokenHexes(background: (0x000000, 0xFCF8F6), surface: (0x0E0B07, 0xFFFFFF),
                       surfaceRaised: (0x19140D, 0xF5EEEA), accent: (0xFE8C32, 0x904807),
                       accentDeep: (0xB66018, 0x834106), accentGlow: (0xF9AE7D, 0xBB6009),
                       accentMuted: (0x7B4318, 0xBE8056), textPrimary: (0xFFF4EE, 0x24180F),
                       textSecondary: (0xC5AD9E, 0x634F41), textTertiary: (0x846F61, 0x705C50),
                       powerIn: (0x7BF5B0, 0x166E3D), warning: (0xF6C763, 0x7C5A00), critical: (0xFF6B7A, 0xB22436),
                       onAccent: (0x000000, 0xFFFFFF))
        case .citrine:
            TokenHexes(background: (0x000000, 0xFAF9F6), surface: (0x0C0C07, 0xFFFFFF),
                       surfaceRaised: (0x15160E, 0xF2F0E9), accent: (0xF9C217, 0x755A07),
                       accentDeep: (0xB18900, 0x6A5206), accentGlow: (0xFBD168, 0x9A7709),
                       accentMuted: (0x655018, 0xA58E57), textPrimary: (0xFCF6E9, 0x201B0C),
                       textSecondary: (0xBCB29A, 0x5B533D), textTertiary: (0x7C745E, 0x68604D),
                       powerIn: (0x7BF5B0, 0x166E3D), warning: (0xFFBF8F, 0x925011), critical: (0xFF6B7A, 0xB22436),
                       onAccent: (0x000000, 0xFFFFFF))
        case .fern:
            TokenHexes(background: (0x000000, 0xF8FAF7), surface: (0x080D0A, 0xFFFFFF),
                       surfaceRaised: (0x0F1713, 0xECF2EC), accent: (0x5EEF17, 0x297107),
                       accentDeep: (0x3EAA00, 0x256706), accentGlow: (0x72FA40, 0x37930A),
                       accentMuted: (0x2B6219, 0x69A258), textPrimary: (0xF1FAEE, 0x141E13),
                       textSecondary: (0xA8B8A3, 0x495846), textTertiary: (0x6A7967, 0x576453),
                       powerIn: (0x5CF7C7, 0x006D53), warning: (0xFFC266, 0x8D5200), critical: (0xFF6B7A, 0xB22436),
                       onAccent: (0x000000, 0xFFFFFF))
        case .graphite:
            TokenHexes(background: (0x000000, 0xF9F9F9), surface: (0x0C0C0C, 0xFFFFFF),
                       surfaceRaised: (0x151515, 0xF0F0F0), accent: (0xB7B7B7, 0x5E5E5E),
                       accentDeep: (0x818181, 0x555555), accentGlow: (0xCECECE, 0x7C7C7C),
                       accentMuted: (0x535353, 0x909090), textPrimary: (0xF7F7F7, 0x1B1B1B),
                       textSecondary: (0xB2B2B2, 0x535353), textTertiary: (0x747474, 0x616161),
                       powerIn: (0x7BF5B0, 0x166E3D), warning: (0xFFC266, 0x8D5200), critical: (0xFF6B7A, 0xB22436),
                       onAccent: (0x000000, 0xFFFFFF))
        }
    }
}
