import AppKit
import BusStopCore
import SwiftUI

/// The "Lagoon" design tokens: turquoise on true black. See docs/SPEC.md §4.
enum Lagoon {
    // MARK: Surfaces

    static let background = Color(hex: 0x000000)
    static let surface = Color(hex: 0x070D0E)
    static let surfaceRaised = Color(hex: 0x0D1719)
    static let stroke = Color(hex: 0x3EE6D4, opacity: 0.16)
    static let strokeStrong = Color(hex: 0x3EE6D4, opacity: 0.34)

    // MARK: Accent

    static let accent = Color(hex: 0x3EE6D4)
    static let accentDeep = Color(hex: 0x0FA3A0)
    static let accentGlow = Color(hex: 0x8AFFF3)
    static let accentMuted = Color(hex: 0x1C5F5A)

    // MARK: Text

    static let textPrimary = Color(hex: 0xEAFBF8)
    static let textSecondary = Color(hex: 0x9BBAB5)
    static let textTertiary = Color(hex: 0x5E7B77)

    // MARK: Status

    static let powerIn = Color(hex: 0x7BF5B0)
    static let warning = Color(hex: 0xFFC266)
    static let critical = Color(hex: 0xFF6B7A)

    // MARK: Text and effects on other colours

    /// Text and icons on an accent fill (the DEMO badge, the active PDO, the Open Topology button).
    static let onAccent = Color(hex: 0x000000)
    /// What hovered strokes and power pulses are mixed toward to stand out from the background.
    static let highlight = Color(hex: 0xFFFFFF)
    /// Drop shadow under floating bubbles such as map tooltips.
    static let shadow = Color(hex: 0x000000, opacity: 0.5)
    /// A faint fill that sets a small preview apart from its card (menu bar icon tiles).
    static let well = Color(hex: 0xFFFFFF, opacity: 0.06)

    // MARK: Menu bar preview (Settings › Menu Bar)

    /// Stand-in for the macOS menu bar, leading to trailing.
    static let menuBarBackdrop = [Color(hex: 0x1B2A3A), Color(hex: 0x0E1A1C)]
    /// The pressed-item highlight behind Bus Stop's item in the preview.
    static let menuBarItemHighlight = Color(hex: 0xFFFFFF, opacity: 0.14)

    // MARK: AppKit equivalents

    static let nsBackground = NSColor(hex: 0x000000)

    // MARK: Geometry

    static let cardRadius: CGFloat = 14
    static let chipRadius: CGFloat = 7
    static let popoverWidth: CGFloat = 380
    static let popoverMaxHeight: CGFloat = 640

    // MARK: Link-speed ramp

    static func linkColor(_ tier: SpeedTier) -> Color {
        switch tier {
        case .legacy: return Color(hex: 0x3C5E5A)
        case .gbps5: return Color(hex: 0x22A69B)
        case .gbps10: return Color(hex: 0x3EE6D4)
        case .gbps20: return Color(hex: 0x5FF0E0)
        case .gbps40: return Color(hex: 0x8AFFF3)
        case .gbps80: return Color(hex: 0xC9FFF9)
        }
    }

    static func linkWidth(_ tier: SpeedTier) -> CGFloat {
        switch tier {
        case .legacy: return 1.5
        case .gbps5: return 2
        case .gbps10: return 2.5
        case .gbps20: return 3
        case .gbps40: return 3.5
        case .gbps80: return 4
        }
    }

    /// Fastest links get a soft glow in the graph.
    static func linkGlows(_ tier: SpeedTier) -> Bool { tier >= .gbps40 }

    /// Colour for text labelled with a speed tier, such as speed chips. The
    /// USB 1/2 ramp colour is meant for link strokes and is too dark for small
    /// text (about 2.7:1 on a card), so that tier uses secondary text; from
    /// 5 Gb/s up the ramp colour itself reads at 5:1 or better.
    static func linkTextColor(_ tier: SpeedTier) -> Color {
        tier == .legacy ? textSecondary : linkColor(tier)
    }

    /// Power-mode link colour: a heat ramp that gets brighter as watts rise,
    /// from grey (no power) through deep red, orange and amber to gold. Each
    /// step is at least 3.4:1 on the map's black and rises in OKLCH
    /// lightness (0.52, 0.64, 0.76, 0.88), so more power always reads as
    /// brighter.
    static func powerColor(_ tier: PowerTier) -> Color {
        switch tier {
        case .none: return Color(hex: 0x636363)
        case .under5: return Color(hex: 0xB6322D)
        case .under15: return Color(hex: 0xDE6129)
        case .under45: return Color(hex: 0xEF9D32)
        case .high: return Color(hex: 0xF6D653)
        }
    }

    static func powerWidth(_ tier: PowerTier) -> CGFloat {
        switch tier {
        case .none: return 1.25
        case .under5: return 1.75
        case .under15: return 2.5
        case .under45: return 3.25
        case .high: return 4
        }
    }

    /// The two strongest power tiers glow, like the fastest links.
    static func powerGlows(_ tier: PowerTier) -> Bool { tier >= .under45 }

    /// Text in a power tier's colour. Grey and deep red are too dark for
    /// small text, so those use secondary text.
    static func powerTextColor(_ tier: PowerTier) -> Color {
        tier <= .under5 ? textSecondary : powerColor(tier)
    }

    /// Popover width for a text size: wider for Large and Extra Large text so
    /// labels do not truncate, never narrower than `popoverWidth`.
    static func popoverWidth(for textSize: TextSizeSetting) -> CGFloat {
        (popoverWidth * max(1, textSize.scale)).rounded()
    }

    static func severityColor(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .info: return accent
        case .warning: return warning
        case .critical: return critical
        }
    }

    static func severitySymbol(_ severity: DiagnosticSeverity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    /// The level's name in the UI, as the Diagnostics page shows it.
    static func severityName(_ severity: DiagnosticSeverity) -> String {
        switch severity {
        case .info: return "Note"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    static func powerColor(_ direction: PowerDirection) -> Color {
        switch direction {
        case .input: return powerIn
        case .output: return accent
        case .none: return textTertiary
        }
    }

    // MARK: Type

    // Fixed-size fonts kept for views not yet on `lagoonFont`, which follows
    // the Text Size setting. Prefer `lagoonFont` in new code.
    static let titleFont = Font.system(.headline, design: .default).weight(.semibold)
    static let machineFont = Font.system(.title3, design: .default).weight(.bold)
    static let valueFont = Font.system(.body, design: .default).monospacedDigit()
    static let chipFont = Font.system(.caption, design: .rounded).weight(.semibold)
    static let captionFont = Font.system(.caption, design: .default)
}

/// Series colours, checked with the dataviz palette validator against the
/// card surface (dark mode): every adjacent pair is distinguishable with and
/// without colour-vision deficiency. Teal comes first so a single series stays
/// on brand; amber and coral are left for warnings.
enum PowerChartPalette {
    static let systemInput = Color(hex: 0x0FA396)
    static let battery = Color(hex: 0x5E7CE2)
    /// Third in the system chart, after battery, as in the validated port order.
    static let systemLoad = Color(hex: 0x45A86A)
    static let ports: [Color] = [systemInput, battery, systemLoad, Color(hex: 0xA56BD8)]
    /// Ports beyond the palette are summed into one neutral series.
    static let otherPorts = Color(hex: 0x7A8A88)
}

// MARK: - Scalable fonts

extension EnvironmentValues {
    /// Text scale from the Text Size setting (1 = medium). Set once at the root
    /// of the popover and each window; read by `lagoonFont`.
    @Entry var lagoonTextScale: CGFloat = 1
}

extension Lagoon {
    /// macOS point sizes of the system text styles at the default size.
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
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
    static func font(_ style: Font.TextStyle, scale: CGFloat, weight: Font.Weight? = nil,
                     design: Font.Design = .default) -> Font {
        let resolvedWeight = weight ?? (style == .headline ? .semibold : .regular)
        return .system(size: (baseSize(style) * scale).rounded(), weight: resolvedWeight, design: design)
    }

    /// A fixed point size scaled by `scale` (for icons and dense chips).
    static func font(size: CGFloat, scale: CGFloat, weight: Font.Weight = .regular,
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
    func lagoonFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design = .default,
                    monospacedDigits: Bool = false) -> some View {
        modifier(LagoonFontModifier(style: style, size: nil, weight: weight, design: design,
                                    monospacedDigits: monospacedDigits))
    }

    /// Fixed-size variant: `.lagoonFont(size: 9, weight: .bold)`.
    func lagoonFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
                    monospacedDigits: Bool = false) -> some View {
        modifier(LagoonFontModifier(style: nil, size: size, weight: weight, design: design,
                                    monospacedDigits: monospacedDigits))
    }

    /// Sets the text scale for everything below (use at view roots).
    func lagoonTextScale(_ setting: TextSizeSetting) -> some View {
        environment(\.lagoonTextScale, setting.scale)
    }
}

extension Color {
    /// `Color(hex: 0x3EE6D4)`
    init(hex: UInt32, opacity: Double = 1) {
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
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// How much power crosses a link, in the steps the map colours by.
nonisolated enum PowerTier: Int, CaseIterable, Comparable, Sendable {
    case none, under5, under15, under45, high

    init(milliwatts: Int) {
        switch milliwatts {
        case ..<1: self = .none
        case ..<5_000: self = .under5
        case ..<15_000: self = .under15
        case ..<45_000: self = .under45
        default: self = .high
        }
    }

    static func < (lhs: PowerTier, rhs: PowerTier) -> Bool { lhs.rawValue < rhs.rawValue }
}
