import AppKit
import BusStopCore
import SwiftUI

/// Opens and tracks the app's windows (topology, settings, about) and handles
/// the accessory-app activation dance.
///
/// Windows are plain `NSWindow`s hosting SwiftUI through `NSHostingController`.
/// Each is created once and reused. While one of them is open the app can
/// show a Dock icon (Settings › General); when the last one closes it goes
/// back to being a menu bar accessory.
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    /// Set once at launch by the app delegate.
    var store: PortStore?

    /// Called before any window is shown. The status item uses it to close
    /// the popover so it does not float over the new window.
    var willShowWindow: (() -> Void)?

    private var topologyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var settingsHost: NSHostingController<SettingsRoot>?
    /// Bumped to rebuild the settings view on a requested tab.
    private var settingsGeneration = 0
    private var aboutWindow: NSWindow?
    /// Whether the topology window is counted in `store.setUIVisible`.
    private var isTopologyCounted = false

    static let topologyAutosaveName = "BusStopTopologyWindow"

    // MARK: Showing windows

    /// Shows the topology window, optionally selecting a port or device first.
    func showTopology(selecting selection: StoreSelection? = nil) {
        guard let store else { return }
        if let selection { store.reveal(selection) }
        let window = topologyWindow ?? makeTopologyWindow(store: store)
        topologyWindow = window
        present(window)
        setTopologyCounted(true)
    }

    /// Shows the settings window. When it is already open and a tab is
    /// given, switches to that tab.
    func showSettings(tab: SettingsTab? = nil) {
        guard let store else { return }
        if let window = settingsWindow, let host = settingsHost {
            if let tab {
                settingsGeneration += 1
                host.rootView = SettingsRoot(store: store, tab: tab, generation: settingsGeneration)
            }
            present(window)
            return
        }

        let host = NSHostingController(rootView: SettingsRoot(store: store, tab: tab ?? .general,
                                                              generation: settingsGeneration))
        // Keep our window title; let the content add toolbar items if it has any.
        host.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: host)
        window.title = "Bus Stop Settings"
        window.styleMask = [.titled, .closable]
        configureCommon(window)
        window.center()
        settingsHost = host
        settingsWindow = window
        present(window)
    }

    /// Re-applies the Dock icon policy (Settings › General) to the windows
    /// that are open right now, so the setting takes effect immediately.
    func refreshActivationPolicy() {}

    /// Shows the About window.
    func showAbout() {
        if let aboutWindow {
            present(aboutWindow)
            return
        }
        let host = NSHostingController(rootView: AboutView())
        host.sceneBridgingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = "About Bus Stop"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        configureCommon(window)
        window.center()
        aboutWindow = window
        present(window)
    }

    // MARK: Window construction

    private func makeTopologyWindow(store: PortStore) -> NSWindow {
        let host = NSHostingController(rootView: TopologyWindowView(store: store))
        // The SwiftUI `.toolbar` and `.navigationTitle` drive the window's.
        host.sceneBridgingOptions = [.toolbars, .title]
        // Only a minimum from the content; the window resizes freely above it.
        host.sizingOptions = [.minSize]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = host
        window.title = "Bus Stop"
        window.toolbarStyle = .unified
        window.contentMinSize = NSSize(width: 900, height: 600)
        configureCommon(window)

        // Setting the content view controller sized the window to the
        // content's fitting size; restore the default, then any saved frame.
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.center()
        if !window.setFrameUsingName(Self.topologyAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.topologyAutosaveName)
        return window
    }

    /// Settings shared by every Bus Stop window.
    private func configureCommon(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.tabbingMode = .disallowed
        window.delegate = self
    }

    /// Brings a window to the front of an accessory app.
    ///
    /// Accessory apps cannot always activate themselves on macOS 26 and later
    /// (platform research §3.2), so the app becomes a regular app while a
    /// window is open when the user allows a Dock icon. `orderFrontRegardless`
    /// makes sure the window is on screen even if activation is refused.
    private func present(_ window: NSWindow) {
        willShowWindow?()
        let showDockIcon = store?.settings.showDockIconWithWindow ?? AppSettings.shared.showDockIconWithWindow
        if showDockIcon {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    // MARK: Visibility bookkeeping

    private func setTopologyCounted(_ counted: Bool) {
        guard counted != isTopologyCounted else { return }
        isTopologyCounted = counted
        store?.setUIVisible(counted)
    }

    private var ourWindows: [NSWindow] {
        [topologyWindow, settingsWindow, aboutWindow].compactMap { $0 }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === topologyWindow {
            setTopologyCounted(false)
        }
        let stillOpen = ourWindows.contains { $0 !== window && ($0.isVisible || $0.isMiniaturized) }
        if !stillOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        if (notification.object as? NSWindow) === topologyWindow {
            setTopologyCounted(false)
        }
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        if (notification.object as? NSWindow) === topologyWindow {
            setTopologyCounted(true)
        }
    }
}

/// Root of the settings window. Changing `generation` gives `SettingsView` a
/// new identity, so it starts again on `tab` even if it keeps its selected
/// tab in `@State`.
struct SettingsRoot: View {
    var store: PortStore
    var tab: SettingsTab
    var generation: Int

    var body: some View {
        SettingsView(store: store, initialTab: tab)
            .id(generation)
    }
}
