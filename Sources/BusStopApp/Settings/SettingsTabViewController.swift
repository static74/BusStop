import AppKit
import SwiftUI

/// The settings window's content: one toolbar tab per `SettingsTab`, with its
/// icon and title, each hosting a `SettingsPaneRoot`.
///
/// AppKit toolbar tabs rather than a SwiftUI `TabView`: in a hosting
/// controller `TabView` becomes an `NSTabView` that centres its tab bar on a
/// half point, so on a 1x display the tab labels blur, and it drops the
/// icons. See docs/decisions.md.
final class SettingsTabViewController: NSTabViewController {
    init(store: PortStore, tab: SettingsTab) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        for settingsTab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsPaneRoot(store: store, tab: settingsTab))
            // The window shows the selected pane's title, as in System Settings.
            host.title = settingsTab.title
            let item = NSTabViewItem(viewController: host)
            item.identifier = settingsTab.rawValue
            item.label = settingsTab.title
            item.image = NSImage(systemSymbolName: settingsTab.symbolName, accessibilityDescription: nil)
            addTabViewItem(item)
        }
        select(tab)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Switches to `tab`. Each pane keeps its state while another is shown.
    func select(_ tab: SettingsTab) {
        selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: tab) ?? 0
    }
}
