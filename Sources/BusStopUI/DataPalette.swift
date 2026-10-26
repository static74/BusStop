import AppKit
import BusStopCore
import SwiftUI

/// Data mode's colours: the link-speed ramp, plus the accent, idle and pulse
/// colours drawn with it on the map. Lagoon is the app's own turquoise. The
/// other presets follow Lagoon's shape (muted at USB 2, most vivid around
/// 10 Gb/s, washing toward white in Dark and toward ink in Light) at the hue
/// of a macOS accent colour, and meet the same contrast rules
/// (`ThemeContrastTests`). Power mode keeps its own colours.
public enum DataPalette: String, CaseIterable, Identifiable {
    case lagoon
    case sky
    case iris
    case orchid
    case ember
    case tangerine
    case citrine
    case fern
    case graphite

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lagoon: return "Lagoon"
        case .sky: return "Sky"
        case .iris: return "Iris"
        case .orchid: return "Orchid"
        case .ember: return "Ember"
        case .tangerine: return "Tangerine"
        case .citrine: return "Citrine"
        case .fern: return "Fern"
        case .graphite: return "Graphite"
        }
    }

    /// OKLCH hue the preset was built at: Lagoon's own, or that of the macOS
    /// accent colour it matches. Nil for Graphite, which has none.
    public var hue: Double? {
        switch self {
        case .lagoon: return 184.3
        case .sky: return 257.4
        case .iris: return 326.5
        case .orchid: return 355.5
        case .ember: return 23.1
        case .tangerine: return 54.0
        case .citrine: return 87.5
        case .fern: return 138.9
        case .graphite: return nil
        }
    }

    /// The preset that best matches `color`: Graphite when it has almost no
    /// chroma (the Graphite accent), otherwise the one with the nearest hue.
    public static func nearest(to color: NSColor) -> DataPalette {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .lagoon }
        let (_, chroma, hue) = oklch(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
        guard chroma >= 0.04 else { return .graphite }
        func distance(_ palette: DataPalette) -> Double {
            guard let other = palette.hue else { return .infinity }
            let gap = abs(other - hue).truncatingRemainder(dividingBy: 360)
            return min(gap, 360 - gap)
        }
        return allCases.min { distance($0) < distance($1) } ?? .lagoon
    }

    /// OKLCH lightness, chroma and hue (degrees) of a gamma-encoded sRGB colour.
    public nonisolated static func oklch(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = (linear(red), linear(green), linear(blue))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let hue = atan2(bb, a) * 180 / .pi
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, (a * a + bb * bb).squareRoot(),
                hue < 0 ? hue + 360 : hue)
    }

    // MARK: Colours

    /// One preset's colours, resolved once.
    public struct Colors {
        /// Indexed by `SpeedTier.rawValue`.
        public var ramp: [Color]
        /// Links with no known rate and active trunks.
        public var accent: Color
        /// Idle trunks.
        public var muted: Color
        /// Pulses on links.
        public var pulse: Color
    }

    /// Built once: each `themed` call makes a new dynamic colour that never
    /// compares equal to another, and the map asks for these on every frame.
    private static let all: [DataPalette: Colors] = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.build()) })

    public var colors: Colors { Self.all[self]! }

    private func build() -> Colors {
        func color(_ pair: (dark: UInt32, light: UInt32)) -> Color { Lagoon.themed(pair.dark, pair.light) }
        return Colors(ramp: hexes.ramp.map(color), accent: color(hexes.accent), muted: color(hexes.muted),
                      pulse: color(hexes.pulse))
    }

    /// (Dark, Light) pairs, one ramp entry per `SpeedTier`. Lagoon's are the
    /// app's own tokens (`accent`, `accentMuted`, `accentGlow`); the others
    /// were generated from Lagoon's lightness and chroma at each preset's hue,
    /// then checked against `ThemeContrastTests`.
    private struct Hexes {
        var ramp: [(dark: UInt32, light: UInt32)]
        var accent: (dark: UInt32, light: UInt32)
        var muted: (dark: UInt32, light: UInt32)
        var pulse: (dark: UInt32, light: UInt32)
    }

    private var hexes: Hexes {
        switch self {
        case .lagoon:
            Hexes(ramp: [(0x3C5E5A, 0x7A9592), (0x22A69B, 0x0B6961), (0x3EE6D4, 0x005A52),
                         (0x5FF0E0, 0x004B44), (0x8AFFF3, 0x003C37), (0xC9FFF9, 0x002E2A)],
                  accent: (0x3EE6D4, 0x096D68), muted: (0x1C5F5A, 0x5E9E97), pulse: (0x8AFFF3, 0x0A8F86))
        case .sky:
            Hexes(ramp: [(0x375682, 0x7B90AF), (0x5398FA, 0x0856B4), (0x74ACFD, 0x03499C),
                         (0x9CC2F9, 0x023C83), (0xCADEFA, 0x01306B), (0xEDF2FA, 0x012454)],
                  accent: (0x74ACFD, 0x075ABC), muted: (0x18519D, 0x6592D2), pulse: (0x9CC2F9, 0x0976F3))
        case .iris:
            Hexes(ramp: [(0x733E74, 0xA97DA9), (0xF445FB, 0x920D97), (0xFA78FE, 0x7E0682),
                         (0xF9A2FA, 0x69046D), (0xFACEFA, 0x550259), (0xFAEDF9, 0x430145)],
                  accent: (0xFA78FE, 0x980B9D), muted: (0x821F85, 0xC663C9), pulse: (0xF9A2FA, 0xC60FCC))
        case .orchid:
            Hexes(ramp: [(0x7C3E57, 0xB37C90), (0xFB5AA4, 0xA20D5F), (0xFE82B5, 0x8C0551),
                         (0xFAA8C7, 0x760443), (0xFAD1DF, 0x600236), (0xFAEEF2, 0x4B0129)],
                  accent: (0xFE82B5, 0xA90A63), muted: (0x901E57, 0xD76394), pulse: (0xFAA8C7, 0xDC0E82))
        case .ember:
            Hexes(ramp: [(0x803F3D, 0xB37F7C), (0xFB6061, 0xAA0D23), (0xFE8581, 0x93061C),
                         (0xF9AAA5, 0x7C0416), (0xFAD2CF, 0x640310), (0xFAEFEE, 0x4F020A)],
                  accent: (0xFE8581, 0xB10B25), muted: (0x961F27, 0xD76B68), pulse: (0xF9AAA5, 0xE60F32))
        case .tangerine:
            Hexes(ramp: [(0x6E4D37, 0xA58876), (0xE77A1C, 0x8A4608), (0xFE8C32, 0x773A03),
                         (0xF9AE7D, 0x643002), (0xFAD4BD, 0x512501), (0xFAF0E9, 0x3F1C01)],
                  accent: (0xFE8C32, 0x904807), muted: (0x7B4318, 0xBE8056), pulse: (0xF9AE7D, 0xBB6009))
        case .citrine:
            Hexes(ramp: [(0x605437, 0x988E76), (0xBB921C, 0x715708), (0xF9C217, 0x614A03),
                         (0xFBD168, 0x513D02), (0xFBE4AD, 0x413002), (0xFAF1DD, 0x322501)],
                  accent: (0xF9C217, 0x755A07), muted: (0x655018, 0xA58E57), pulse: (0xFBD168, 0x9A7709))
        case .fern:
            Hexes(ramp: [(0x405F38, 0x7E9777), (0x46AD1B, 0x286C09), (0x5EEF17, 0x205D04),
                         (0x72FA40, 0x194D03), (0xB8FCA5, 0x123E02), (0xE3FADC, 0x0C3001)],
                  accent: (0x5EEF17, 0x297107), muted: (0x2B6219, 0x69A258), pulse: (0x72FA40, 0x37930A))
        case .graphite:
            Hexes(ramp: [(0x555555, 0x8E8E8E), (0x9E9E9E, 0x5B5B5B), (0xB7B7B7, 0x4D4D4D),
                         (0xCECECE, 0x404040), (0xE1E1E1, 0x333333), (0xF2F2F2, 0x272727)],
                  accent: (0xB7B7B7, 0x5E5E5E), muted: (0x535353, 0x909090), pulse: (0xCECECE, 0x7C7C7C))
        }
    }
}
