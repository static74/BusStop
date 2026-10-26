import AppKit
import BusStopCore
import BusStopUI
import Foundation
import SwiftUI
import Testing
@testable import BusStopApp

/// Data mode's colour presets: the setting, Lagoon staying as it was, the
/// presets reading as well as Lagoon in Dark, and the system accent mapping.
@MainActor
@Suite("Data colour presets")
struct DataPaletteTests {
    typealias RGB = ThemeContrastTests.RGB

    @Test func settingRoundTripAndReset() {
        let suite = "BusStopAppTests.DataPalette.roundTrip"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!

        let settings = AppSettings(defaults: defaults)
        #expect(settings.dataColor == .preset(.lagoon))
        settings.dataColor = .preset(.ember)
        #expect(defaults.string(forKey: "dataColor") == "ember")
        #expect(AppSettings(defaults: defaults).dataColor == .preset(.ember))
        settings.dataColor = .system
        #expect(AppSettings(defaults: defaults).dataColor == .system)

        defaults.set("plaid", forKey: "dataColor")
        #expect(AppSettings(defaults: defaults).dataColor == .preset(.lagoon))

        settings.dataColor = .preset(.iris)
        settings.resetAll()
        #expect(settings.dataColor == .preset(.lagoon))
        #expect(AppSettings.Key.all.contains("dataColor"))
    }

    @Test func everySettingHasARawValue() {
        #expect(DataColorSetting.allCases.count == DataPalette.allCases.count + 1)
        for setting in DataColorSetting.allCases {
            #expect(DataColorSetting(rawValue: setting.rawValue) == setting)
        }
        #expect(DataColorSetting.system.resolved(system: .fern) == .fern)
        #expect(DataColorSetting.preset(.sky).resolved(system: .fern) == .sky)
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func lagoonIsTodaysLook(_ scheme: ColorScheme) {
        let colors = DataPalette.lagoon.colors
        let pairs: [(Color, Color)] = [
            (colors.accent, Lagoon.accent), (colors.muted, Lagoon.accentMuted), (colors.pulse, Lagoon.accentGlow),
        ]
        for (palette, token) in pairs {
            #expect(ThemeContrastTests.rgb(palette, scheme).isClose(to: ThemeContrastTests.rgb(token, scheme),
                                                                     within: 0.001))
        }
    }

    @Test func everyRampHasOneColourPerTier() {
        for palette in DataPalette.allCases {
            #expect(palette.colors.ramp.count == SpeedTier.allCases.count, "\(palette)")
        }
    }

    /// The dark ramp is not held to contrast targets of its own (its values
    /// are Lagoon's, frozen), so presets are held to Lagoon: no speed chip
    /// may read worse than Lagoon's at the same tier, or below 4.5:1 where
    /// Lagoon reaches it.
    @Test func darkChipsReadAtLeastAsWellAsLagoon() {
        let raised = ThemeContrastTests.rgb(Lagoon.surfaceRaised, .dark)
        func ratio(_ tier: SpeedTier, _ palette: DataPalette, fill: Double, text: Double) -> Double {
            let background = ThemeContrastTests.rgb(Lagoon.linkColor(tier, palette), .dark).over(raised, opacity: fill)
            return ThemeContrastTests.rgb(Lagoon.linkTextColor(tier, palette), .dark)
                .over(background, opacity: text).contrast(with: background)
        }
        for tier in SpeedTier.allCases {
            for (fill, text) in [(0.12, 1.0), (0.10, Lagoon.textFade(0.8, .dark))] {
                let target = min(4.5, ratio(tier, .lagoon, fill: fill, text: text)) - 0.01
                for palette in DataPalette.allCases {
                    #expect(ratio(tier, palette, fill: fill, text: text) >= target, "\(palette) \(tier) \(fill)")
                }
            }
        }
    }

    /// macOS accent colours (Dark and Light variants) pick the preset made
    /// for them; Multicolor's blue picks Sky.
    @Test(arguments: [
        (UInt32(0x007AFF), DataPalette.sky), (0x0A84FF, .sky), (0xA550A7, .iris), (0x953D96, .iris),
        (0xF74F9E, .orchid), (0xE45C9C, .orchid), (0xFF5257, .ember), (0xE0383E, .ember), (0xF7821B, .tangerine),
        (0xFFC600, .citrine), (0x62BA46, .fern), (0x8C8C8C, .graphite), (0x3EE6D4, .lagoon),
    ])
    func accentColoursPickTheirPreset(_ hex: UInt32, _ expected: DataPalette) {
        let color = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        #expect(DataPalette.nearest(to: color) == expected)
    }

    @Test func oklchMatchesKnownValues() {
        let (l, c, h) = DataPalette.oklch(red: 0x3E / 255, green: 0xE6 / 255, blue: 0xD4 / 255)
        #expect(abs(l - 0.84) < 0.01)
        #expect(abs(c - 0.135) < 0.005)
        #expect(abs(h - 184.3) < 1)
        #expect(DataPalette.oklch(red: 0.5, green: 0.5, blue: 0.5).1 < 0.001)
    }
}
