import AppKit
import BusStopCore

/// App lifecycle: forces the dark appearance, runs as a menu bar accessory,
/// creates the store, the menu bar item and the main menu, and wires events
/// to notifications.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: PortStore?
    private var statusItemController: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Always dark: the Lagoon look is true black (docs/SPEC.md §9).
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make(delegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings.shared
        let store = PortStore(settings: settings)
        self.store = store
        WindowManager.shared.store = store

        statusItemController = StatusItemController(store: store, settings: settings)

        store.onEvents = { events in
            NotificationManager.shared.post(events, settings: settings)
        }
        if Self.wantsAnyNotification(settings) {
            Task {
                // Prompts only when permission was never asked for.
                _ = await NotificationManager.shared.requestAuthorization()
            }
        }

        store.start()

        // With the menu bar item hidden there is no other way in, so open
        // the topology window.
        if !settings.showMenuBarItem {
            WindowManager.shared.showTopology()
        }

        Automation.run(statusItemController: statusItemController)
    }

    func applicationWillTerminate(_ notification: Notification) {
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
        NSWorkspace.shared.open(MainMenu.projectURL)
    }
}
