import AppKit
import BusStopCore
import SwiftUI

/// The "Lagoon" design tokens: turquoise on black in Dark, on near-white in
/// Light, or the chosen colour preset's hue in its place. Every colour follows
/// the appearance it is drawn in. See docs/SPEC.md §4.
public enum Lagoon {
    // MARK: Surfaces, accent, text and status

    // These follow `LagoonTheme.shared.palette`; the values for each preset
    // are in ThemeTokens.swift, and Lagoon's are the defaults below.

    private static var tokens: LagoonTokens { LagoonTheme.shared.palette.tokens }

    public static var background: Color { tokens.background }
    public static var surface: Color { tokens.surface }
    public static var surfaceRaised: Color { tokens.surfaceRaised }
    public static var stroke: Color { tokens.stroke }
    public static var strokeStrong: Color { tokens.strokeStrong }

    public static var accent: Color { tokens.accent }
    public static var accentDeep: Color { tokens.accentDeep }
    public static var accentGlow: Color { tokens.accentGlow }
    public static var accentMuted: Color { tokens.accentMuted }

    public static var textPrimary: Color { tokens.textPrimary }
    public static var textSecondary: Color { tokens.textSecondary }
    public static var textTertiary: Color { tokens.textTertiary }

    public static var powerIn: Color { tokens.powerIn }
    public static var warning: Color { tokens.warning }
    public static var critical: Color { tokens.critical }

    // MARK: Text and effects on other colours

    /// Text and icons on an accent fill (the Demo badge, the active PDO, the Open Map button).
    public static var onAccent: Color { tokens.onAccent }
    /// What a hovered or selected link's core is mixed toward to stand out:
    /// white makes it brighter in Dark, black makes it darker in Light.
    public static let linkHighlightMix = themed(0xFFFFFF, 0x000000)
    /// What power pulses are mixed toward, so the dots read as light on the link.
    public static let pulseMix = themed(0xFFFFFF, 0xFFFFFF)
    /// Drop shadow under floating bubbles such as map tooltips.
    public static let shadow = themed(0x000000, 0x000000, opacity: 0.5, lightOpacity: 0.15)
    /// A faint fill that sets a small preview apart from its card (menu bar icon tiles).
    public static let well = themed(0xFFFFFF, 0x0B1F1D, opacity: 0.06)

    // MARK: Menu bar preview (Settings › Menu Bar)

    /// Stand-in for the macOS menu bar, leading to trailing.
    public static let menuBarBackdrop = [themed(0x1B2A3A, 0xE4ECEB), themed(0x0E1A1C, 0xF2F6F5)]
    /// The pressed-item highlight behind Bus Stop's item in the preview.
    public static let menuBarItemHighlight = themed(0xFFFFFF, 0x0B1F1D, opacity: 0.14)

    // MARK: AppKit equivalents

    public static var nsBackground: NSColor { tokens.nsBackground }

    // MARK: Theme helpers

    /// A colour that follows the appearance it is drawn in: `dark` under Dark
    /// Aqua (and its high-contrast variant), `light` under Aqua.
    public nonisolated static func themed(_ dark: UInt32, _ light: UInt32, opacity: CGFloat = 1,
                                   lightOpacity: CGFloat? = nil) -> Color {
        Color(nsColor: themedNS(dark, light, opacity: opacity, lightOpacity: lightOpacity))
    }

    /// AppKit resolves dynamic colours on any thread, so the provider must not
    /// inherit the main actor (see `StatusIcon.drawSign`).
    public nonisolated static func themedNS(_ dark: UInt32, _ light: UInt32, opacity: CGFloat = 1,
                                     lightOpacity: CGFloat? = nil) -> NSColor {
        NSColor(name: nil) { @Sendable appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua
                ? NSColor(hex: light, alpha: lightOpacity ?? opacity)
                : NSColor(hex: dark, alpha: opacity)
        }
    }

    /// Opacity for softened text: Dark keeps the softer look, Light draws the
    /// text at full ink, because faded dark text on white falls below 4.5:1.
    public nonisolated static func textFade(_ opacity: Double, _ scheme: ColorScheme) -> Double {
        scheme == .dark ? opacity : 1
    }

    // MARK: Geometry

    public static let cardRadius: CGFloat = 14
    public static let popoverWidth: CGFloat = 380
    public static let popoverMaxHeight: CGFloat = 640

    // MARK: Link-speed ramp

    /// Link-stroke colour in `palette`: brighter as speed rises in Dark,
    /// darker in Light, so faster links always carry more contrast.
    public static func linkColor(_ tier: SpeedTier, _ palette: DataPalette) -> Color {
        palette.colors.ramp[tier.rawValue]
    }

    public static func linkWidth(_ tier: SpeedTier) -> CGFloat {
        switch tier {
        case .legacy: return 1.5
        case .gbps5: return 2
        case .gbps10: return 2.5
        case .gbps20: return 3
        case .gbps40: return 3.5
        case .gbps80: return 4
        }
    }

    /// Fastest links get a soft glow in the graph (Dark only; Light draws no glows).
    public static func linkGlows(_ tier: SpeedTier) -> Bool { tier >= .gbps40 }

    /// Colour for text labelled with a speed tier, such as speed chips. The
    /// USB 1/2 ramp colour is meant for link strokes and is too dark for small
    /// text (about 2.7:1 on a card), so that tier uses secondary text; from
    /// 5 Gb/s up the ramp colour itself reads at 5:1 or better. The light ramp
    /// was chosen so the same rule holds in both themes (`ThemeContrastTests`).
    public static func linkTextColor(_ tier: SpeedTier, _ palette: DataPalette) -> Color {
        tier == .legacy ? textSecondary : linkColor(tier, palette)
    }

    /// Power-mode link colour: a heat ramp that gets brighter as watts rise
    /// in Dark, from grey (no power) through deep red, orange and amber to
    /// gold, each step at least 3.4:1 on the map's black and rising in OKLCH
    /// lightness (0.52, 0.64, 0.76, 0.88). In Light it gets darker instead,
    /// from gold to deep red (OKLCH lightness falling from 0.62 to 0.40), so
    /// more power always means more ink.
    public static func powerColor(_ tier: PowerTier) -> Color { powerRamp[tier.rawValue] }

    /// Built once, like `DataPalette`'s colours.
    private static let powerRamp: [Color] = PowerTier.allCases.map { tier in
        switch tier {
        case .none: return themed(0x636363, 0x858585)
        case .under5: return themed(0xB6322D, 0x9B7300)
        case .under15: return themed(0xDE6129, 0x994A00)
        case .under45: return themed(0xEF9D32, 0x9A2B16)
        case .high: return themed(0xF6D653, 0x831922)
        }
    }

    public static func powerWidth(_ tier: PowerTier) -> CGFloat {
        switch tier {
        case .none: return 1.25
        case .under5: return 1.75
        case .under15: return 2.5
        case .under45: return 3.25
        case .high: return 4
        }
    }

    /// The two strongest power tiers glow, like the fastest links (Dark only).
    public static func powerGlows(_ tier: PowerTier) -> Bool { tier >= .under45 }

    /// Text in a power tier's colour. The two lowest tiers are too faint for
    /// small text in either theme, so those use secondary text.
    public static func powerTextColor(_ tier: PowerTier) -> Color {
        tier <= .under5 ? textSecondary : powerColor(tier)
    }

    public static func severityColor(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .info: return accent
        case .warning: return warning
        case .critical: return critical
        }
    }

    public static func severitySymbol(_ severity: DiagnosticSeverity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    /// The level's name in the UI, as the Diagnostics page shows it.
    public static func severityName(_ severity: DiagnosticSeverity) -> String {
        switch severity {
        case .info: return "Note"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    public static func powerColor(_ direction: PowerDirection) -> Color {
        switch direction {
        case .input: return powerIn
        case .output: return accent
        case .none: return textTertiary
        }
    }
}

/// Series colours, checked with the dataviz palette validator against the
/// card surfaces of each theme: every adjacent pair is distinguishable with
/// and without colour-vision deficiency. Only the deliberately neutral
/// `otherPorts` is below the chroma floor. Teal comes first so a single
/// series stays on brand; amber and coral are left for warnings.
public enum PowerChartPalette {
    public static let systemInput = Lagoon.themed(0x0FA396, 0x00887B)
    public static let battery = Lagoon.themed(0x5E7CE2, 0x4A66CC)
    /// Third in the system chart, after battery, as in the validated port order.
    public static let systemLoad = Lagoon.themed(0x45A86A, 0x2F8A50)
    public static let ports: [Color] = [systemInput, battery, systemLoad, Lagoon.themed(0xA56BD8, 0x8E52C2)]
    /// Ports beyond the palette are summed into one neutral series.
    public static let otherPorts = Lagoon.themed(0x7A8A88, 0x6B7A78)
}

// MARK: - Scalable fonts

extension EnvironmentValues {
    /// Text scale from the Text Size setting (1 = medium). Set once at the root
    /// of the popover and each window; read by `lagoonFont`.
    @Entry public var lagoonTextScale: CGFloat = 1
    /// Data mode's colours, set at view roots from Settings › Appearance.
    @Entry public var dataPalette: DataPalette = .lagoon
}

extension Lagoon {
    /// macOS point sizes of the system text styles at the default size.
    public static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 26
        case .title: return 22
        case .title2: return 17
        case .title3: return 15
        case .headline: return 13
        case .subheadline: return 11
        case .body: return 13
        case .callout: return 12
        case .footnote: return 10
        case .caption: return 10
        case .caption2: return 10
        @unknown default: return 13
        }
    }

    /// A system font for `style` scaled by `scale`. Headline defaults to semibold
    /// as on macOS.
    public static func font(_ style: Font.TextStyle, scale: CGFloat, weight: Font.Weight? = nil,
                     design: Font.Design = .default) -> Font {
        let resolvedWeight = weight ?? (style == .headline ? .semibold : .regular)
        return .system(size: (baseSize(style) * scale).rounded(), weight: resolvedWeight, design: design)
    }

    /// A fixed point size scaled by `scale` (for icons and dense chips).
    public static func font(size: CGFloat, scale: CGFloat, weight: Font.Weight = .regular,
                     design: Font.Design = .default) -> Font {
        .system(size: (size * scale).rounded(), weight: weight, design: design)
    }
}

/// Applies a text style scaled by the Text Size setting.
struct LagoonFontModifier: ViewModifier {
    var style: Font.TextStyle?
    var size: CGFloat?
    var weight: Font.Weight?
    var design: Font.Design
    var monospacedDigits: Bool
    @Environment(\.lagoonTextScale) private var scale

    func body(content: Content) -> some View {
        let font: Font
        if let size {
            font = Lagoon.font(size: size, scale: scale, weight: weight ?? .regular, design: design)
        } else {
            font = Lagoon.font(style ?? .body, scale: scale, weight: weight, design: design)
        }
        return content.font(monospacedDigits ? font.monospacedDigit() : font)
    }
}

extension View {
    /// `.lagoonFont(.caption, weight: .semibold)`: like `.font(.caption)` but
    /// honours the Text Size setting. Use this instead of `.font` in app views.
    public func lagoonFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design = .default,
                    monospacedDigits: Bool = false) -> some View {
        modifier(LagoonFontModifier(style: style, size: nil, weight: weight, design: design,
                                    monospacedDigits: monospacedDigits))
    }

    /// Fixed-size variant: `.lagoonFont(size: 9, weight: .bold)`.
    public func lagoonFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
                    monospacedDigits: Bool = false) -> some View {
        modifier(LagoonFontModifier(style: nil, size: size, weight: weight, design: design,
                                    monospacedDigits: monospacedDigits))
    }
}

extension Color {
    /// `Color(hex: 0x3EE6D4)`
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension NSColor {
    public nonisolated convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// How much power crosses a link, in the steps the map colours by.
public nonisolated enum PowerTier: Int, CaseIterable, Comparable, Sendable {
    case none, under5, under15, under45, high

    public init(milliwatts: Int) {
        switch milliwatts {
        case ..<1: self = .none
        case ..<5_000: self = .under5
        case ..<15_000: self = .under15
        case ..<45_000: self = .under45
        default: self = .high
        }
    }

    public static func < (lhs: PowerTier, rhs: PowerTier) -> Bool { lhs.rawValue < rhs.rawValue }
}
