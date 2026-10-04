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
    var store: PortStore? {
        didSet { observeDockIconSetting() }
    }

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

    /// Re-applies the activation policy whenever the Dock icon setting changes.
    private var dockIconObservation: ObservationLoop?
    /// True while the app is a regular app only until a pending activation
    /// goes through, because the user turned the Dock icon off.
    private var isBorrowingRegularPolicy = false
    private var activationObserver: NSObjectProtocol?
    /// The window to keep in front once the borrowed activation ends.
    private weak var windowAwaitingActivation: NSWindow?

    static let topologyAutosaveName = "BusStopTopologyWindow"
    /// Content size of a new topology window when the screen has room.
    static let preferredTopologySize = NSSize(width: 1280, height: 820)
    /// The smallest content size the topology window allows.
    static let minimumTopologySize = NSSize(width: 900, height: 600)

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
        // Centred once, at its real size; later it opens where the user left it.
        sizeToContent(window, host: host)
        window.center()
        settingsHost = host
        settingsWindow = window
        present(window)
    }

    /// Re-applies the Dock icon policy (Settings › General) to the windows
    /// that are open right now, so the setting takes effect immediately: a
    /// regular app with a Dock icon while a Bus Stop window is open and the
    /// setting is on, a menu bar accessory otherwise. Runs by itself whenever
    /// the setting changes; safe to call at any time.
    func refreshActivationPolicy() {
        applyActivationPolicy(closing: nil)
    }

    /// Makes Bus Stop the active app before an app-modal panel (a save panel
    /// or an alert), so the panel opens in front and takes the keyboard even
    /// when it was started from the menu bar's menu. Call
    /// `refreshActivationPolicy()` once the panel has closed.
    func activateForModal() {
        if !NSApp.isActive && NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
    }

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
        sizeToContent(window, host: host)
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

        let defaultSize = Self.defaultTopologySize(for: NSScreen.main)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = host
        window.title = "Bus Stop"
        window.toolbarStyle = .unified
        window.contentMinSize = Self.minimumTopologySize
        configureCommon(window)

        // Setting the content view controller sized the window to the
        // content's fitting size; restore the default, then any saved frame,
        // so a size the user chose wins.
        window.setContentSize(defaultSize)
        window.center()
        if !window.setFrameUsingName(Self.topologyAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.topologyAutosaveName)
        return window
    }

    /// `preferredTopologySize` when the screen's visible area has room for it
    /// with the title bar, toolbar and a margin; otherwise as much as fits,
    /// but never below `minimumTopologySize`.
    static func defaultTopologySize(for screen: NSScreen?) -> NSSize {
        let preferred = preferredTopologySize
        guard let visible = screen?.visibleFrame, visible.width > 0, visible.height > 0 else { return preferred }
        let width = min(preferred.width, visible.width - 80)
        let height = min(preferred.height, visible.height - 120)
        return NSSize(width: max(minimumTopologySize.width, width), height: max(minimumTopologySize.height, height))
    }

    /// Sizes a new window to its SwiftUI content before it is shown, so
    /// `center()` works with the real size. Without this the window is still
    /// empty when it is centred and then grows from the middle of the screen
    /// towards the bottom right.
    private func sizeToContent<Content: View>(_ window: NSWindow, host: NSHostingController<Content>) {
        let fitting = host.sizeThatFits(in: CGSize(width: 4000, height: 4000))
        guard fitting.width >= 1, fitting.height >= 1, fitting.width < 4000, fitting.height < 4000 else { return }
        window.setContentSize(fitting)
    }

    /// Settings shared by every Bus Stop window.
    private func configureCommon(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.tabbingMode = .disallowed
        window.delegate = self
    }

    /// Brings a window to the front of an accessory app and gives it the
    /// keyboard.
    ///
    /// An accessory app with no window on screen is often refused activation
    /// on macOS 26 and later (platform research §3.2): the window opens
    /// behind the frontmost app, or in front but without focus, so typing
    /// still goes to the other app. A regular app is activated reliably, so
    /// Bus Stop becomes one first. With the Dock icon allowed it stays regular
    /// while a window is open; with the Dock icon turned off it goes back to
    /// being an accessory as soon as the activation has gone through.
    /// `orderFrontRegardless` keeps the window on screen even if activation
    /// is refused.
    private func present(_ window: NSWindow) {
        willShowWindow?()
        let needsRegularPolicy = !NSApp.isActive && NSApp.activationPolicy() != .regular
        if showDockIcon || needsRegularPolicy {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        if !showDockIcon && needsRegularPolicy {
            returnToAccessoryAfterActivation(keeping: window)
        }
    }

    private var showDockIcon: Bool {
        store?.settings.showDockIconWithWindow ?? AppSettings.shared.showDockIconWithWindow
    }

    // MARK: Activation policy

    private func observeDockIconSetting() {
        dockIconObservation = ObservationLoop { [weak self] in
            guard let self else { return }
            // Read inside the loop so a change (or Reset All) re-runs it.
            _ = self.store?.settings.showDockIconWithWindow
            self.refreshActivationPolicy()
        }
    }

    /// Regular with a Dock icon while a window stays open and the user wants
    /// the icon; an accessory otherwise. `closing` is a window that is about
    /// to close and no longer counts.
    private func applyActivationPolicy(closing: NSWindow?) {
        // A borrowed activation settles the policy itself when it ends.
        guard !isBorrowingRegularPolicy else { return }
        let openWindows = ourWindows.filter { $0 !== closing && ($0.isVisible || $0.isMiniaturized) }
        let policy: NSApplication.ActivationPolicy = showDockIcon && !openWindows.isEmpty ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        let keyWindow = openWindows.first { $0.isKeyWindow }
        NSApp.setActivationPolicy(policy)
        // Changing the policy can send the open window behind other apps.
        if let front = keyWindow ?? openWindows.first(where: { $0.isVisible }) {
            NSApp.activate()
            front.makeKeyAndOrderFront(nil)
        }
    }

    /// With the Dock icon turned off, the app was made regular only to get
    /// activated. Goes back to being an accessory once the activation has
    /// gone through, or after a second if it never does.
    private func returnToAccessoryAfterActivation(keeping window: NSWindow) {
        isBorrowingRegularPolicy = true
        windowAwaitingActivation = window
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.endBorrowedActivation()
            }
        }
        if NSApp.isActive {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.endBorrowedActivation()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated {
                self?.endBorrowedActivation()
            }
        }
    }

    private func endBorrowedActivation() {
        guard isBorrowingRegularPolicy else { return }
        isBorrowingRegularPolicy = false
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        let window = windowAwaitingActivation
        windowAwaitingActivation = nil
        applyActivationPolicy(closing: nil)
        // Leaving the regular policy can drop focus; give it back.
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
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
        applyActivationPolicy(closing: window)
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
