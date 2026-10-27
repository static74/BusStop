import AppKit
import Testing
@testable import BusStopApp

/// The settings window uses AppKit toolbar tabs, not a SwiftUI `TabView`,
/// whose tab bar sat on a half point and blurred on 1x displays (see
/// `SettingsTabViewController` and docs/decisions.md).
@MainActor
@Suite("Settings tabs", .serialized)
struct SettingsTabsTests {
    /// The settings window `WindowManager.showSettings` shows.
    private func makeWindow(tab: SettingsTab) -> (NSWindow, SettingsTabViewController, () -> Void) {
        let suite = "BusStopAppTests.SettingsTabs"
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.demoMode = true
        let store = PortStore(settings: settings)
        let (window, tabs) = WindowManager.makeSettingsWindow(store: store, tab: tab)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.layoutIfNeeded()
        }
        return (window, tabs, {
            window.close()
            UserDefaults.standard.removePersistentDomain(forName: suite)
        })
    }

    @Test func everyTabIsAToolbarItemWithItsIconAndTitle() throws {
        let (window, _, close) = makeWindow(tab: .general)
        defer { close() }
        let toolbar = try #require(window.toolbar)
        // Only the tabs: AppKit adds its own spacers around them.
        let titles = SettingsTab.allCases.map(\.title)
        let items = toolbar.items.filter { titles.contains($0.label) }
        #expect(items.map(\.label) == titles)
        #expect(items.allSatisfy { $0.image != nil })
    }

    @Test func opensOnTheRequestedTabAndSwitches() {
        let (window, tabs, close) = makeWindow(tab: .appearance)
        defer { close() }
        #expect(tabs.selectedTabViewItemIndex == SettingsTab.allCases.firstIndex(of: .appearance))
        #expect(window.title == "Appearance")
        tabs.select(.ports)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(tabs.selectedTabViewItemIndex == SettingsTab.allCases.firstIndex(of: .ports))
        #expect(window.title == "Ports")
        #expect(window.contentLayoutRect.size == SettingsPaneRoot.size)
    }
}
