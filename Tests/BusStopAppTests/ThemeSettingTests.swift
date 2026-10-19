import AppKit
import Foundation
import Testing
@testable import BusStopApp

/// The theme setting: where it is stored, its default, Reset All, and the
/// appearance each choice sets on the app.
@MainActor
@Suite("Theme setting")
struct ThemeSettingTests {
    @Test func themeSettingRoundTripAndReset() {
        let suite = "BusStopAppTests.ThemeSetting.roundTrip"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!

        let settings = AppSettings(defaults: defaults)
        #expect(settings.theme == .dark)

        settings.theme = .light
        #expect(defaults.string(forKey: "theme") == "light")
        #expect(AppSettings(defaults: defaults).theme == .light)
        settings.theme = .system
        #expect(AppSettings(defaults: defaults).theme == .system)

        // An unknown value falls back to the default.
        defaults.set("sepia", forKey: "theme")
        #expect(AppSettings(defaults: defaults).theme == .dark)

        settings.theme = .light
        settings.resetAll()
        #expect(settings.theme == .dark)
        #expect(AppSettings.Key.all.contains("theme"))
    }

    @Test func themeMapsToAppearance() {
        #expect(ThemeSetting.dark.appearance?.name == .darkAqua)
        #expect(ThemeSetting.light.appearance?.name == .aqua)
        #expect(ThemeSetting.system.appearance == nil)
    }
}
