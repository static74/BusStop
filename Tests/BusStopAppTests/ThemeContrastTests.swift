import AppKit
import BusStopCore
import BusStopUI
import SwiftUI
import Synchronization
import Testing
@testable import BusStopApp

/// Every Lagoon colour in both themes: Dark resolves to the frozen hex
/// values, and Light meets the contrast targets in docs/decisions.md.
@MainActor
@Suite("Theme contrast")
struct ThemeContrastTests {
    /// A gamma-encoded sRGB colour with its alpha, as WCAG works with it.
    struct RGB {
        var r, g, b, a: Double

        init(_ resolved: Color.Resolved) {
            r = Double(resolved.red); g = Double(resolved.green); b = Double(resolved.blue)
            a = Double(resolved.opacity)
        }

        init(r: Double, g: Double, b: Double, a: Double = 1) {
            self.r = r; self.g = g; self.b = b; self.a = a
        }

        /// This colour at `opacity` times its own alpha, over an opaque `background`.
        func over(_ background: RGB, opacity: Double = 1) -> RGB {
            let alpha = a * opacity
            return RGB(r: r * alpha + background.r * (1 - alpha),
                       g: g * alpha + background.g * (1 - alpha),
                       b: b * alpha + background.b * (1 - alpha))
        }

        private static func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }

        var luminance: Double {
            0.2126 * Self.linear(r) + 0.7152 * Self.linear(g) + 0.0722 * Self.linear(b)
        }

        /// OKLab lightness (the L of OKLCH).
        var oklchLightness: Double {
            let (lr, lg, lb) = (Self.linear(r), Self.linear(g), Self.linear(b))
            let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
            let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
            let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
            return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        }

        func contrast(with other: RGB) -> Double {
            let (x, y) = (luminance, other.luminance)
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }

        func isClose(to other: RGB, within tolerance: Double) -> Bool {
            abs(r - other.r) <= tolerance && abs(g - other.g) <= tolerance && abs(b - other.b) <= tolerance
                && abs(a - other.a) <= tolerance
        }
    }

    static func rgb(_ color: Color, _ scheme: ColorScheme) -> RGB {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return RGB(color.resolve(in: environment))
    }

    static func surfaces(_ scheme: ColorScheme) -> [RGB] {
        [Lagoon.background, Lagoon.surface, Lagoon.surfaceRaised].map { rgb($0, scheme) }
    }

    /// The lowest contrast of `color` over each surface, composited.
    static func worstContrast(_ color: Color, _ scheme: ColorScheme) -> Double {
        surfaces(scheme).map { rgb(color, scheme).over($0).contrast(with: $0) }.min() ?? 0
    }

    /// Today's Dark hex values, frozen.
    static let darkHex: [(String, Color, Color)] = [
        ("background", Lagoon.background, Color(hex: 0x000000)),
        ("surface", Lagoon.surface, Color(hex: 0x070D0E)),
        ("surfaceRaised", Lagoon.surfaceRaised, Color(hex: 0x0D1719)),
        ("stroke", Lagoon.stroke, Color(hex: 0x3EE6D4, opacity: 0.16)),
        ("strokeStrong", Lagoon.strokeStrong, Color(hex: 0x3EE6D4, opacity: 0.34)),
        ("accent", Lagoon.accent, Color(hex: 0x3EE6D4)),
        ("accentDeep", Lagoon.accentDeep, Color(hex: 0x0FA3A0)),
        ("accentGlow", Lagoon.accentGlow, Color(hex: 0x8AFFF3)),
        ("accentMuted", Lagoon.accentMuted, Color(hex: 0x1C5F5A)),
        ("textPrimary", Lagoon.textPrimary, Color(hex: 0xEAFBF8)),
        ("textSecondary", Lagoon.textSecondary, Color(hex: 0x9BBAB5)),
        ("textTertiary", Lagoon.textTertiary, Color(hex: 0x5E7B77)),
        ("powerIn", Lagoon.powerIn, Color(hex: 0x7BF5B0)),
        ("warning", Lagoon.warning, Color(hex: 0xFFC266)),
        ("critical", Lagoon.critical, Color(hex: 0xFF6B7A)),
        ("onAccent", Lagoon.onAccent, Color(hex: 0x000000)),
        ("linkHighlightMix", Lagoon.linkHighlightMix, Color(hex: 0xFFFFFF)),
        ("pulseMix", Lagoon.pulseMix, Color(hex: 0xFFFFFF)),
        ("shadow", Lagoon.shadow, Color(hex: 0x000000, opacity: 0.5)),
        ("well", Lagoon.well, Color(hex: 0xFFFFFF, opacity: 0.06)),
        ("menuBarBackdrop[0]", Lagoon.menuBarBackdrop[0], Color(hex: 0x1B2A3A)),
        ("menuBarBackdrop[1]", Lagoon.menuBarBackdrop[1], Color(hex: 0x0E1A1C)),
        ("menuBarItemHighlight", Lagoon.menuBarItemHighlight, Color(hex: 0xFFFFFF, opacity: 0.14)),
        ("link.legacy", Lagoon.linkColor(.legacy, .lagoon), Color(hex: 0x3C5E5A)),
        ("link.gbps5", Lagoon.linkColor(.gbps5, .lagoon), Color(hex: 0x22A69B)),
        ("link.gbps10", Lagoon.linkColor(.gbps10, .lagoon), Color(hex: 0x3EE6D4)),
        ("link.gbps20", Lagoon.linkColor(.gbps20, .lagoon), Color(hex: 0x5FF0E0)),
        ("link.gbps40", Lagoon.linkColor(.gbps40, .lagoon), Color(hex: 0x8AFFF3)),
        ("link.gbps80", Lagoon.linkColor(.gbps80, .lagoon), Color(hex: 0xC9FFF9)),
        ("power.none", Lagoon.powerColor(PowerTier.none), Color(hex: 0x636363)),
        ("power.under5", Lagoon.powerColor(.under5), Color(hex: 0xB6322D)),
        ("power.under15", Lagoon.powerColor(.under15), Color(hex: 0xDE6129)),
        ("power.under45", Lagoon.powerColor(.under45), Color(hex: 0xEF9D32)),
        ("power.high", Lagoon.powerColor(.high), Color(hex: 0xF6D653)),
        ("chart.systemInput", PowerChartPalette.systemInput, Color(hex: 0x0FA396)),
        ("chart.battery", PowerChartPalette.battery, Color(hex: 0x5E7CE2)),
        ("chart.systemLoad", PowerChartPalette.systemLoad, Color(hex: 0x45A86A)),
        ("chart.port4", PowerChartPalette.ports[3], Color(hex: 0xA56BD8)),
        ("chart.otherPorts", PowerChartPalette.otherPorts, Color(hex: 0x7A8A88)),
    ]

    @Test func darkTokensMatchTodaysHex() {
        for (name, token, hex) in Self.darkHex {
            #expect(Self.rgb(token, .dark).isClose(to: Self.rgb(hex, .dark), within: 0.5 / 255), "\(name)")
        }
        #expect(PowerChartPalette.ports.count == 4)
        let nsDark = Lagoon.nsBackground.resolved(.darkAqua)
        #expect(nsDark.redComponent == 0 && nsDark.greenComponent == 0 && nsDark.blueComponent == 0)
    }

    /// The map asks for ramp colours on every frame; a fresh dynamic colour
    /// per call would never compare equal and would allocate each time.
    @Test func rampColoursAreStable() {
        for palette in DataPalette.allCases {
            for tier in SpeedTier.allCases {
                #expect(Lagoon.linkColor(tier, palette) == Lagoon.linkColor(tier, palette))
            }
            #expect(palette.colors.pulse == palette.colors.pulse)
        }
        for tier in PowerTier.allCases { #expect(Lagoon.powerColor(tier) == Lagoon.powerColor(tier)) }
    }

    @Test func lightTextMeetsContrastTargets() {
        let targets: [(String, Color, Double)] = [
            ("textPrimary", Lagoon.textPrimary, 12),
            ("textSecondary", Lagoon.textSecondary, 6),
            ("textTertiary", Lagoon.textTertiary, 4.5),
            ("accent", Lagoon.accent, 4.5),
            ("powerIn", Lagoon.powerIn, 4.5),
            ("warning", Lagoon.warning, 4.5),
            ("critical", Lagoon.critical, 4.5),
        ]
        for (name, color, target) in targets {
            #expect(Self.worstContrast(color, .light) >= target, "\(name)")
        }
    }

    @Test func lightLinksAndSeriesReachThreeToOne() {
        var colors: [(String, Color)] = [("accentGlow", Lagoon.accentGlow)]
        for palette in DataPalette.allCases {
            colors += SpeedTier.allCases.filter { $0 > .legacy }.map {
                ("\(palette) link \($0)", Lagoon.linkColor($0, palette))
            }
            colors.append(("\(palette) pulse", palette.colors.pulse))
        }
        colors += PowerTier.allCases.filter { $0 > .none }.map { ("power \($0)", Lagoon.powerColor($0)) }
        colors += PowerChartPalette.ports.enumerated().map { ("chart port \($0.offset)", $0.element) }
        colors.append(("chart otherPorts", PowerChartPalette.otherPorts))
        for (name, color) in colors {
            #expect(Self.worstContrast(color, .light) >= 3, "\(name)")
        }
    }

    @Test func dimTokensReadAtLeastAsWellAsInDark() {
        let dim: [(String, Color)] = [
            ("accentMuted", Lagoon.accentMuted),
            ("power none", Lagoon.powerColor(PowerTier.none)),
        ] + DataPalette.allCases.flatMap { palette in
            [("\(palette) link legacy", Lagoon.linkColor(.legacy, palette)), ("\(palette) muted", palette.colors.muted)]
        }
        for (name, color) in dim {
            for (dark, light) in zip(Self.surfaces(.dark), Self.surfaces(.light)) {
                let darkRatio = Self.rgb(color, .dark).contrast(with: dark)
                let lightRatio = Self.rgb(color, .light).contrast(with: light)
                #expect(lightRatio >= darkRatio, "\(name)")
            }
        }
    }

    @Test func chipTextReadsOnItsOwnFill() {
        let raised = Self.rgb(Lagoon.surfaceRaised, .light)
        let surface = Self.rgb(Lagoon.surface, .light)
        /// Text at `textOpacity` on its own colour at `fillOpacity`, over `base`.
        func ratio(_ text: Color, textOpacity: Double = 1, on fill: Color, at fillOpacity: Double,
                   over base: RGB) -> Double {
            let background = Self.rgb(fill, .light).over(base, opacity: fillOpacity)
            return Self.rgb(text, .light).over(background, opacity: textOpacity).contrast(with: background)
        }

        for palette in DataPalette.allCases {
            for tier in SpeedTier.allCases {
                let text = Lagoon.linkTextColor(tier, palette), fill = Lagoon.linkColor(tier, palette)
                #expect(ratio(text, on: fill, at: 0.12, over: raised) >= 4.5, "\(palette) speed chip \(tier)")
                // TransportChip: the rate at its faded opacity on the 0.10 fill.
                #expect(ratio(text, textOpacity: Lagoon.textFade(0.8, .light), on: fill, at: 0.10, over: raised) >= 4.5,
                        "\(palette) transport rate \(tier)")
            }
            // A chip with no known rate uses the palette's accent.
            let accent = palette.colors.accent
            #expect(ratio(accent, on: accent, at: 0.12, over: raised) >= 4.5, "\(palette) accent chip")
        }
        for tier in PowerTier.allCases {
            #expect(ratio(Lagoon.powerTextColor(tier), on: Lagoon.powerColor(tier), at: 0.12, over: raised) >= 4.5,
                    "power chip \(tier)")
        }
        let own: [(String, Color)] = [
            ("accent", Lagoon.accent), ("powerIn", Lagoon.powerIn), ("textTertiary", Lagoon.textTertiary),
            ("warning", Lagoon.warning), ("critical", Lagoon.critical),
        ]
        for (name, color) in own {
            #expect(ratio(color, on: color, at: 0.12, over: raised) >= 4.5, "\(name) on own fill")
        }
        // PowerBadge: a budget at its faded opacity on the 0.10 fill.
        for direction in [PowerDirection.input, .output, .none] {
            let color = Lagoon.powerColor(direction)
            #expect(ratio(color, textOpacity: Lagoon.textFade(0.75, .light), on: color, at: 0.10, over: raised) >= 4.5,
                    "power badge \(direction)")
        }
        // The inspector's raw-key names, straight on the raised surface.
        let key = Self.rgb(Lagoon.accent, .light).over(raised, opacity: Lagoon.textFade(0.85, .light))
        #expect(key.contrast(with: raised) >= 4.5)
        // DiagnosticTitle's severity chip: 0.14 fill on a Diagnostics card.
        for severity in [DiagnosticSeverity.info, .warning, .critical] {
            let color = Lagoon.severityColor(severity)
            #expect(ratio(color, on: color, at: 0.14, over: surface) >= 4.5, "severity chip \(severity)")
        }
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func onAccentReadsOnAccentFills(_ scheme: ColorScheme) {
        let text = Self.rgb(Lagoon.onAccent, scheme)
        #expect(text.contrast(with: Self.rgb(Lagoon.accent, scheme)) >= 4.5)
        #expect(text.contrast(with: Self.rgb(Lagoon.accentDeep, scheme)) >= 4.5)
    }

    @Test func rampsAreMonotonicInLightness() {
        func lightness(_ colors: [Color], _ scheme: ColorScheme) -> [Double] {
            colors.map { Self.rgb($0, scheme).oklchLightness }
        }
        func rises(_ values: [Double]) -> Bool { zip(values, values.dropFirst()).allSatisfy { $0 < $1 } }
        func falls(_ values: [Double]) -> Bool { zip(values, values.dropFirst()).allSatisfy { $0 > $1 } }
        for palette in DataPalette.allCases {
            let links = SpeedTier.allCases.map { Lagoon.linkColor($0, palette) }
            #expect(rises(lightness(links, .dark)), "\(palette)")
            #expect(falls(lightness(links, .light)), "\(palette)")
        }
        let powers = PowerTier.allCases.map { Lagoon.powerColor($0) }
        #expect(rises(lightness(powers, .dark)))
        #expect(falls(lightness(powers, .light)))
    }

    /// `GraphPaint.solid` must blend where it is drawn. A mix that resolved
    /// early would blend with black and draw grey links on white.
    @Test func solidMixBlendsWithTheThemeBackground() throws {
        let solid = GraphPaint.solid(Lagoon.accent, opacity: 0.42)
        let accent = Self.rgb(Lagoon.accent, .light)
        let expected = accent.over(Self.rgb(Lagoon.background, .light), opacity: 0.42)
        let overBlack = accent.over(RGB(r: 0, g: 0, b: 0), opacity: 0.42)
        let resolved = Self.rgb(solid, .light)
        #expect(resolved.isClose(to: expected, within: 1 / 255))
        #expect(!resolved.isClose(to: overBlack, within: 0.1))

        // The same inside a Canvas, as the map draws it.
        let canvas = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(solid))
        }
        .frame(width: 4, height: 4)
        .environment(\.colorScheme, .light)
        let image = try #require(ImageRenderer(content: canvas).cgImage)
        let pixel = try #require(Self.centrePixel(image))
        #expect(pixel.isClose(to: expected, within: 2 / 255))
    }

    @Test func highContrastAppearancesPickTheirTheme() {
        let color = Lagoon.themedNS(0x000000, 0xFFFFFF)
        #expect(color.resolved(.accessibilityHighContrastAqua).redComponent == 1)
        #expect(color.resolved(.accessibilityHighContrastDarkAqua).redComponent == 0)
        #expect(color.resolved(.aqua).redComponent == 1)
        #expect(color.resolved(.darkAqua).redComponent == 0)

        let faded = Lagoon.themedNS(0x000000, 0x000000, opacity: 0.5, lightOpacity: 0.15)
        #expect(abs(faded.resolved(.aqua).alphaComponent - 0.15) < 0.001)
        #expect(abs(faded.resolved(.accessibilityHighContrastAqua).alphaComponent - 0.15) < 0.001)
        #expect(abs(faded.resolved(.darkAqua).alphaComponent - 0.5) < 0.001)
        #expect(abs(faded.resolved(.accessibilityHighContrastDarkAqua).alphaComponent - 0.5) < 0.001)
    }

    /// AppKit resolves dynamic colours on any thread. A provider that
    /// inherited the main actor would trap here.
    @Test func providerRunsOffTheMainThread() async {
        let red = await Task.detached { () -> CGFloat in
            Lagoon.themedNS(0x000000, 0xFFFFFF).resolved(.aqua).redComponent
        }.value
        #expect(red == 1)
    }

    @Test func legendLabelsDescribeEachTheme() {
        #expect(GraphSpeedLegend.accessibilityText(.dark)
            == "Link colours: dim for USB 2, brighter and thicker for faster links, glowing at 40 gigabits per second and above")
        #expect(GraphPowerLegend.accessibilityText(.dark)
            == "Power colours: grey for no power, then deep red, orange, amber and gold as watts rise. Pulses move the way the power flows. Values marked with a less-than-or-equal sign are USB power budgets, not measurements.")
        #expect(SilhouetteStateLegend.spokenText(.power, .dark)
            == "Port colours by power: dim for empty, then deep red, orange, amber and gold as watts rise")
        #expect(SilhouetteStateLegend.spokenText(.data, .light) == SilhouetteStateLegend.spokenText(.data, .dark))

        let light = [
            GraphSpeedLegend.accessibilityText(.light),
            GraphPowerLegend.accessibilityText(.light),
            SilhouetteStateLegend.spokenText(.power, .light),
        ]
        for text in light {
            #expect(!text.contains("glowing") && !text.contains("brighter"), "\(text)")
        }
        for text in light.dropFirst() {
            let gold = text.range(of: "gold")?.lowerBound
            let red = text.range(of: "deep red")?.lowerBound
            #expect(gold != nil && red != nil && gold! < red!, "\(text)")
        }
    }

    // MARK: Presets

    /// OKLCH hue of `color` in `scheme`, in degrees.
    static func hue(_ color: Color, _ scheme: ColorScheme) -> Double {
        let c = rgb(color, scheme)
        return DataPalette.oklch(red: c.r, green: c.g, blue: c.b).2
    }

    static func hueGap(_ a: Double, _ b: Double) -> Double {
        let gap = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(gap, 360 - gap)
    }

    /// Lagoon's tokens are the ones the frozen Dark values above check.
    @Test func lagoonPresetIsTheDefault() {
        #expect(LagoonTheme.shared.palette == .lagoon)
        #expect(Lagoon.accent == DataPalette.lagoon.tokens.accent)
    }

    /// Every preset's interface colours meet Lagoon's Light targets on its own surfaces.
    @Test(arguments: DataPalette.allCases)
    func presetTokensMeetContrastTargets(_ palette: DataPalette) {
        let t = palette.tokens
        let surfaces = [t.background, t.surface, t.surfaceRaised].map { Self.rgb($0, .light) }
        func worst(_ color: Color) -> Double {
            surfaces.map { Self.rgb(color, .light).over($0).contrast(with: $0) }.min() ?? 0
        }
        let raised = Self.rgb(t.surfaceRaised, .light)
        func onOwnFill(_ color: Color, at opacity: Double) -> Double {
            let fill = Self.rgb(color, .light).over(raised, opacity: opacity)
            return Self.rgb(color, .light).contrast(with: fill)
        }
        let targets: [(String, Color, Double)] = [
            ("textPrimary", t.textPrimary, 12), ("textSecondary", t.textSecondary, 6),
            ("textTertiary", t.textTertiary, 4.5), ("accent", t.accent, 4.5), ("powerIn", t.powerIn, 4.5),
            ("warning", t.warning, 4.5), ("critical", t.critical, 4.5),
        ]
        for (name, color, target) in targets {
            #expect(worst(color) >= target, "\(palette) \(name)")
        }
        for (name, color) in [("accent", t.accent), ("powerIn", t.powerIn), ("warning", t.warning),
                              ("critical", t.critical)] {
            #expect(onOwnFill(color, at: 0.12) >= 4.5, "\(palette) \(name) on own fill")
        }
        #expect(worst(t.accentGlow) >= 3, "\(palette) accentGlow")
        for scheme in [ColorScheme.dark, .light] {
            let text = Self.rgb(t.onAccent, scheme)
            #expect(text.contrast(with: Self.rgb(t.accent, scheme)) >= 4.5, "\(palette) onAccent on accent \(scheme)")
            #expect(text.contrast(with: Self.rgb(t.accentDeep, scheme)) >= 4.5, "\(palette) onAccent on deep \(scheme)")
        }
        #expect(Self.rgb(t.background, .dark).luminance == 0, "\(palette) Dark background is black")
    }

    /// Status colours stay at least 27° of hue from the preset's accent and
    /// from each other, so a warning never reads as decoration (2026-10-31).
    @Test(arguments: DataPalette.allCases)
    func statusColoursStayApartFromThePreset(_ palette: DataPalette) {
        let t = palette.tokens
        for scheme in [ColorScheme.dark, .light] {
            let status = [("powerIn", t.powerIn), ("warning", t.warning), ("critical", t.critical)]
                .map { ($0.0, Self.hue($0.1, scheme)) }
            if let presetHue = palette.hue {
                for (name, hue) in status {
                    #expect(Self.hueGap(hue, presetHue) >= 27, "\(palette) \(name) \(scheme)")
                }
            }
            for (a, b) in [(0, 1), (0, 2), (1, 2)] {
                #expect(Self.hueGap(status[a].1, status[b].1) >= 27, "\(palette) \(status[a].0)/\(status[b].0) \(scheme)")
            }
        }
    }

    /// A view that draws with a token is told to redraw when the preset changes.
    @Test func tokenReadsAreObserved() {
        let changed = Mutex(false)
        withObservationTracking { _ = Lagoon.surface } onChange: { changed.withLock { $0 = true } }
        LagoonTheme.shared.palette = .ember
        defer { LagoonTheme.shared.palette = .lagoon }
        #expect(changed.withLock { $0 })
        #expect(Lagoon.accent == DataPalette.ember.tokens.accent)
    }

    /// The centre pixel of `image`, in sRGB.
    static func centrePixel(_ image: CGImage) -> RGB? {
        var bytes = [UInt8](repeating: 0, count: 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                       width: CGFloat(image.width), height: CGFloat(image.height)))
        return RGB(r: Double(bytes[0]) / 255, g: Double(bytes[1]) / 255, b: Double(bytes[2]) / 255,
                   a: Double(bytes[3]) / 255)
    }
}

extension NSColor {
    /// This colour as `appearance` draws it, in sRGB.
    nonisolated func resolved(_ appearance: NSAppearance.Name) -> NSColor {
        var result = self
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            result = self.usingColorSpace(.sRGB) ?? self
        }
        return result
    }
}
