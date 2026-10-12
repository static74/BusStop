// Portions adapted from WhatPort (MIT License, © 2025 Darryl Morley).
// The left/right-click routing, the temporarily attached context menu and the
// popover re-anchoring follow WhatPort's AppDelegate.swift.

import AppKit
import BusStopCore
import SwiftUI

/// Owns the menu bar item, its popover and its right-click menu, and keeps
/// the item's icon, text and visibility in sync with the store and settings.
final class StatusItemController: NSObject, NSPopoverDelegate {
    let statusItem: NSStatusItem
    private let popover: NSPopover
    private let store: PortStore
    private let settings: AppSettings

    private var observation: ObservationLoop?
    private var statusItemMoveObserver: NSObjectProtocol?
    /// Whether the popover is currently counted in `store.setUIVisible`.
    private var isPopoverCounted = false
    private var currentIconStyle: MenuBarIconStyle?
    private var currentTitle: String?

    init(store: PortStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        statusItem.autosaveName = "BusStopStatusItem"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // Left click toggles the popover; right click (or Control-click)
            // opens the menu. Both arrive through one action.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        configurePopover()
        observeStatusItemMoves()

        observation = ObservationLoop { [weak self] in
            self?.updateStatusItem()
        }

        WindowManager.shared.willShowWindow = { [weak self] in
            self?.closePopover()
        }
    }

    // MARK: Popover

    var isPopoverShown: Bool { popover.isShown }

    /// Shows the popover under the menu bar item and activates the app so the
    /// popover takes keyboard focus. Falls back to the topology window when
    /// the menu bar item is hidden.
    func showPopover() {
        guard settings.showMenuBarItem, statusItem.isVisible, let button = statusItem.button else {
            WindowManager.shared.showTopology()
            return
        }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        popover.contentSize = NSSize(width: Lagoon.popoverWidth(for: settings.textSize), height: 420)

        let hosting = NSHostingController(rootView: PopoverView(store: store))
        // The SwiftUI content measures itself (fixed width, height up to
        // Lagoon.popoverMaxHeight) and the popover follows.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
    }

    func popoverDidShow(_ notification: Notification) {
        setPopoverCounted(true)
    }

    func popoverDidClose(_ notification: Notification) {
        setPopoverCounted(false)
    }

    /// Keeps `store.setUIVisible` calls balanced however the popover closes.
    private func setPopoverCounted(_ counted: Bool) {
        guard counted != isPopoverCounted else { return }
        isPopoverCounted = counted
        store.setUIVisible(counted)
    }

    // MARK: Clicks

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isMenuClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isMenuClick {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        // Close at once (no animation) so the menu does not overlap it.
        if popover.isShown {
            popover.close()
            setPopoverCounted(false)
        }
        // Attach the menu just long enough for it to pop from the item, then
        // detach it so a later left click toggles the popover again.
        statusItem.menu = makeContextMenu()
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "Bus Stop")

        menu.addItem(item("Open Topology", #selector(openTopology(_:))))
        menu.addItem(item("Refresh", #selector(refresh(_:))))

        let exportItem = NSMenuItem(title: "Export", action: nil, keyEquivalent: "")
        let exportMenu = NSMenu(title: "Export")
        for kind in ExportKind.allCases {
            let exportKindItem = item(kind.title, #selector(export(_:)))
            exportKindItem.representedObject = kind.rawValue
            exportMenu.addItem(exportKindItem)
        }
        exportItem.submenu = exportMenu
        menu.addItem(exportItem)

        menu.addItem(item("Settings\u{2026}", #selector(openSettings(_:))))
        menu.addItem(item("About Bus Stop", #selector(openAbout(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Bus Stop", #selector(quit(_:))))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func openTopology(_ sender: Any?) {
        WindowManager.shared.showTopology()
    }

    @objc private func refresh(_ sender: Any?) {
        store.refresh()
    }

    @objc private func export(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = ExportKind(rawValue: raw) else { return }
        ExportController.export(kind, store: store)
    }

    @objc private func openSettings(_ sender: Any?) {
        WindowManager.shared.showSettings()
    }

    @objc private func openAbout(_ sender: Any?) {
        WindowManager.shared.showAbout()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    // MARK: Icon, text and visibility

    /// Reads the store and settings (inside the observation loop) and pushes
    /// the result into the status item. Only changed values are written.
    private func updateStatusItem() {
        let wantsVisible = settings.showMenuBarItem
        let iconStyle = settings.menuBarIcon
        let textMode = settings.menuBarText
        let precision = settings.menuBarPowerPrecision
        let snapshot = store.snapshot
        let hasLoaded = store.hasLoaded

        if statusItem.isVisible != wantsVisible {
            if !wantsVisible { closePopover() }
            statusItem.isVisible = wantsVisible
        }

        guard let button = statusItem.button else { return }

        if iconStyle != currentIconStyle {
            button.image = StatusIcon.image(for: iconStyle)
            currentIconStyle = iconStyle
        }

        let deviceCount = snapshot.deviceCount
        let headline = PopoverText.headlineMilliwatts(for: snapshot)
        let title = hasLoaded
            ? Self.menuBarText(mode: textMode, deviceCount: deviceCount, milliwatts: headline, precision: precision)
            : ""
        if title != currentTitle {
            currentTitle = title
            if title.isEmpty {
                button.attributedTitle = NSAttributedString(string: "")
                button.imagePosition = .imageOnly
            } else {
                button.attributedTitle = Self.attributedTitle(title)
                button.imagePosition = .imageLeading
            }
        }

        let description = Self.accessibilityDescription(hasLoaded: hasLoaded, deviceCount: deviceCount,
                                                        milliwatts: headline)
        button.setAccessibilityLabel(description)
        button.toolTip = description
    }

    /// "5 · 38W", "38W", "5" or "" depending on the text setting, with the
    /// power rounded as the precision setting asks ("38W", "38.2W"). The
    /// Menu Bar settings preview uses this too, so both always match.
    static func menuBarText(mode: MenuBarTextMode, deviceCount: Int, milliwatts: Int?,
                            precision: PowerPrecision = .automatic) -> String {
        let power = milliwatts.map { Format.compactPower(milliwatts: $0, decimals: precision.decimals) }
        switch mode {
        case .none:
            return ""
        case .power:
            return power ?? ""
        case .devices:
            return "\(deviceCount)"
        case .both:
            if let power { return "\(deviceCount) \u{00B7} \(power)" }
            return "\(deviceCount)"
        }
    }

    /// Monospaced digits so the item does not jitter as the numbers change.
    private static func attributedTitle(_ text: String) -> NSAttributedString {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        // A leading space separates the text from the icon.
        return NSAttributedString(string: " " + text, attributes: [.font: font])
    }

    /// "Bus Stop: 5 devices, 38 W".
    private static func accessibilityDescription(hasLoaded: Bool, deviceCount: Int, milliwatts: Int?) -> String {
        guard hasLoaded else { return "Bus Stop: reading ports" }
        var parts = [deviceCount == 1 ? "1 device" : "\(deviceCount) devices"]
        if let milliwatts { parts.append(Format.power(milliwatts: milliwatts)) }
        return "Bus Stop: " + parts.joined(separator: ", ")
    }

    // MARK: Re-anchoring

    /// Changing the title resizes the item and the menu bar slides it to a new
    /// spot a moment later. An open popover keeps its old anchor, so re-point
    /// it whenever the item's window moves.
    private func observeStatusItemMoves() {
        guard let window = statusItem.button?.window else { return }
        statusItemMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reanchorPopover()
            }
        }
    }

    private func reanchorPopover() {
        guard popover.isShown, let button = statusItem.button else { return }
        popover.positioningRect = button.bounds
    }
}
