import AppKit
import BusStopCore

/// App lifecycle: applies the theme setting, runs as a menu bar accessory,
/// creates the store, the menu bar item and the main menu, and wires events
/// to notifications.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: PortStore?
    private var statusItemController: StatusItemController?
    private var themeLoop: ObservationLoop?
    /// A `busstop://` link that arrived before the store existed.
    private var pendingLink: BusStopLink?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before any window exists, and again on every change, so open
        // windows switch too. Windows and the popover inherit it.
        themeLoop = ObservationLoop { NSApp.appearance = AppSettings.shared.theme.appearance }
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make(delegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings.shared
        let store = PortStore(settings: settings, historyFile: HistoryFile(directory: HistoryFile.standardDirectory))
        self.store = store
        WindowManager.shared.store = store

        statusItemController = StatusItemController(store: store, settings: settings)

        store.onEvents = { [weak store] events in
            // Demo data never notifies; the store does not report it either.
            guard let store, !store.isDemo else { return }
            NotificationManager.shared.post(events, settings: settings, diagnostics: store.snapshot.diagnostics)
        }
        if Self.wantsAnyNotification(settings) {
            Task {
                // Prompts only when permission was never asked for.
                _ = await NotificationManager.shared.requestAuthorization()
            }
        }

        store.start()

        // With the menu bar item hidden there is no other way in, so open
        // the topology window. Automation opens its own view instead, on the
        // page it asks for.
        if !settings.showMenuBarItem && Automation.request == nil {
            WindowManager.shared.showTopology()
        }

        Automation.run(statusItemController: statusItemController)
        if let pendingLink {
            self.pendingLink = nil
            WindowManager.shared.open(pendingLink)
        }
    }

    /// `busstop://` links from widgets. Anything `BusStopLink` does not
    /// parse is ignored.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let link = urls.compactMap(BusStopLink.init(url:)).last else { return }
        if store == nil {
            pendingLink = link
        } else {
            WindowManager.shared.open(link)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.flushHistory()
        store?.stop()
    }

    /// Launching the app again while it runs opens the popover (or the
    /// topology window when the menu bar item is hidden). A click on the Dock
    /// icon while a window is open keeps the standard behaviour and brings
    /// that window forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag && NSApp.activationPolicy() == .regular {
            return true
        }
        if AppSettings.shared.showMenuBarItem, let statusItemController {
            statusItemController.showPopover()
        } else {
            WindowManager.shared.showTopology()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private static func wantsAnyNotification(_ settings: AppSettings) -> Bool {
        settings.notifyConnect || settings.notifyDisconnect || settings.notifyDowngrade
            || settings.notifyCharger || settings.notifyDiagnostics
    }

    // MARK: Menu actions

    @objc func openAbout(_ sender: Any?) {
        WindowManager.shared.showAbout()
    }

    @objc func openSettings(_ sender: Any?) {
        WindowManager.shared.showSettings()
    }

    @objc func refreshPorts(_ sender: Any?) {
        store?.refresh()
    }

    @objc func openTopology(_ sender: Any?) {
        WindowManager.shared.showTopology()
    }

    @objc func openProjectPage(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: BusStopVersion.projectURL)!)
    }
}
