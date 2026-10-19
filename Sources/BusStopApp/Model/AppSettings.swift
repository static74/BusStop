import BusStopCore
import Foundation
import Observation
import SwiftUI

/// Menu bar icon choices.
enum MenuBarIconStyle: String, CaseIterable, Identifiable {
    /// Custom-drawn bus-stop sign (default).
    case busStop
    case connector
    case bolt
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .busStop: return "Bus Stop sign"
        case .connector: return "Cable connector"
        case .bolt: return "Bolt"
        case .grid: return "Ports grid"
        }
    }

    /// SF Symbol, or nil for the custom-drawn sign.
    var symbolName: String? {
        switch self {
        case .busStop: return nil
        case .connector: return "cable.connector"
        case .bolt: return "bolt.horizontal.fill"
        case .grid: return "square.grid.2x2"
        }
    }
}

/// What the status item shows next to its icon.
enum MenuBarTextMode: String, CaseIterable, Identifiable {
    case none
    case power
    case devices
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Icon only"
        case .power: return "Total power"
        case .devices: return "Device count"
        case .both: return "Devices and power"
        }
    }
}

/// What a pinned port shows in the menu bar.
enum PinnedPortValue: String, CaseIterable, Identifiable {
    case power
    case speed
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power: return "Power"
        case .speed: return "Link speed"
        case .both: return "Speed and power"
        }
    }
}

enum PortOrder: String, CaseIterable, Identifiable {
    case physical
    case connectedFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .physical: return "Physical order"
        case .connectedFirst: return "Connected first"
        }
    }
}

/// How the popover lists ports.
enum PopoverLayout: String, CaseIterable, Identifiable {
    /// A card per port with chips and the device tree (default).
    case cards
    /// One line per port; a disclosure shows the device tree.
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cards: return "Cards"
        case .compact: return "Compact"
        }
    }
}

/// How many decimals the menu bar shows for power.
enum PowerPrecision: String, CaseIterable, Identifiable {
    /// "38W" (one decimal below 10 W: "4.5W").
    case automatic
    /// Always whole watts: "38W", "5W".
    case whole
    /// Always one decimal: "38.2W", "4.5W".
    case oneDecimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .whole: return "Whole watts"
        case .oneDecimal: return "One decimal"
        }
    }

    /// Decimals passed to `Format.compactPower(milliwatts:decimals:)`; nil means automatic.
    var decimals: Int? {
        switch self {
        case .automatic: return nil
        case .whole: return 0
        case .oneDecimal: return 1
        }
    }
}

/// The app's look. Dark is the Lagoon default; Match System follows System
/// Settings › Appearance.
enum ThemeSetting: String, CaseIterable, Identifiable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "Match System"
        }
    }

    /// The appearance set on `NSApp`; nil lets the app follow the system.
    var appearance: NSAppearance? {
        switch self {
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        case .system: return nil
        }
    }
}

enum TextSizeSetting: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    /// Multiplier applied to every font through `lagoonFont(_:)`. macOS does not
    /// scale text styles with `dynamicTypeSize`, so Bus Stop scales sizes itself.
    var scale: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.15
        case .extraLarge: return 1.3
        }
    }
}

/// User preferences, persisted in `UserDefaults`.
///
/// One shared instance; views read it through the environment and AppKit
/// controllers hold a reference. Every stored property writes through on change.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: General

    var showMenuBarItem: Bool { didSet { defaults.set(showMenuBarItem, forKey: Key.showMenuBarItem) } }
    var showDockIconWithWindow: Bool { didSet { defaults.set(showDockIconWithWindow, forKey: Key.showDockIconWithWindow) } }
    var hideEmptyPorts: Bool { didSet { defaults.set(hideEmptyPorts, forKey: Key.hideEmptyPorts) } }
    var portOrder: PortOrder { didSet { defaults.set(portOrder.rawValue, forKey: Key.portOrder) } }
    var popoverLayout: PopoverLayout { didSet { defaults.set(popoverLayout.rawValue, forKey: Key.popoverLayout) } }

    // MARK: Menu bar

    var menuBarIcon: MenuBarIconStyle { didSet { defaults.set(menuBarIcon.rawValue, forKey: Key.menuBarIcon) } }
    var menuBarText: MenuBarTextMode { didSet { defaults.set(menuBarText.rawValue, forKey: Key.menuBarText) } }
    var menuBarPowerPrecision: PowerPrecision {
        didSet { defaults.set(menuBarPowerPrecision.rawValue, forKey: Key.menuBarPowerPrecision) }
    }
    /// `hw.model` (or `"demo:<hw.model>"` in demo mode) → `PortKey.description` of the
    /// port pinned to the menu bar. Use `PortStore.pinPort` rather than writing this directly.
    var menuBarPinnedPorts: [String: String] {
        didSet { defaults.set(menuBarPinnedPorts, forKey: Key.menuBarPinnedPorts) }
    }
    var menuBarPinnedValue: PinnedPortValue {
        didSet { defaults.set(menuBarPinnedValue.rawValue, forKey: Key.menuBarPinnedValue) }
    }

    // MARK: Appearance

    var theme: ThemeSetting { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    /// Opacity of the background behind popover and window content (0.6…1).
    var backgroundOpacity: Double { didSet { defaults.set(backgroundOpacity, forKey: Key.backgroundOpacity) } }
    /// Strength of the turquoise tint on glass controls (0…0.5).
    var glassTint: Double { didSet { defaults.set(glassTint, forKey: Key.glassTint) } }
    var textSize: TextSizeSetting { didSet { defaults.set(textSize.rawValue, forKey: Key.textSize) } }
    var animateLinks: Bool { didSet { defaults.set(animateLinks, forKey: Key.animateLinks) } }

    // MARK: Notifications

    var notifyConnect: Bool { didSet { defaults.set(notifyConnect, forKey: Key.notifyConnect) } }
    var notifyDisconnect: Bool { didSet { defaults.set(notifyDisconnect, forKey: Key.notifyDisconnect) } }
    var notifyDowngrade: Bool { didSet { defaults.set(notifyDowngrade, forKey: Key.notifyDowngrade) } }
    var notifyCharger: Bool { didSet { defaults.set(notifyCharger, forKey: Key.notifyCharger) } }
    var notifyDiagnostics: Bool { didSet { defaults.set(notifyDiagnostics, forKey: Key.notifyDiagnostics) } }

    // MARK: Advanced

    /// Seconds between power refreshes while UI is visible (1, 2 or 5).
    var powerPollInterval: Double { didSet { defaults.set(powerPollInterval, forKey: Key.powerPollInterval) } }
    var readSMC: Bool { didSet { defaults.set(readSMC, forKey: Key.readSMC) } }
    var showRawKeys: Bool { didSet { defaults.set(showRawKeys, forKey: Key.showRawKeys) } }
    var redactExports: Bool { didSet { defaults.set(redactExports, forKey: Key.redactExports) } }
    var demoMode: Bool { didSet { defaults.set(demoMode, forKey: Key.demoMode) } }
    var demoScenario: DemoScenario { didSet { defaults.set(demoScenario.rawValue, forKey: Key.demoScenario) } }
    /// Save the event log, power and port counters between launches. Change
    /// it through `PortStore.setKeepHistory`, which deletes the file when it
    /// goes off.
    var keepHistory: Bool { didSet { defaults.set(keepHistory, forKey: Key.keepHistory) } }

    // MARK: Ports

    /// `"<hw.model>#<port key>"` (e.g. `"Mac16,5#2/1"`) → user name. Use
    /// `PortStore.renamePort` rather than writing this directly.
    var portNames: [String: String] { didSet { defaults.set(portNames, forKey: Key.portNames) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        func double(_ key: String, _ fallback: Double) -> Double {
            defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
        }
        func string(_ key: String) -> String? { defaults.string(forKey: key) }

        showMenuBarItem = bool(Key.showMenuBarItem, true)
        showDockIconWithWindow = bool(Key.showDockIconWithWindow, true)
        hideEmptyPorts = bool(Key.hideEmptyPorts, false)
        portOrder = string(Key.portOrder).flatMap(PortOrder.init(rawValue:)) ?? .physical
        popoverLayout = string(Key.popoverLayout).flatMap(PopoverLayout.init(rawValue:)) ?? .cards
        menuBarIcon = string(Key.menuBarIcon).flatMap(MenuBarIconStyle.init(rawValue:)) ?? .busStop
        menuBarText = string(Key.menuBarText).flatMap(MenuBarTextMode.init(rawValue:)) ?? .power
        menuBarPowerPrecision = string(Key.menuBarPowerPrecision).flatMap(PowerPrecision.init(rawValue:)) ?? .automatic
        menuBarPinnedPorts = (defaults.dictionary(forKey: Key.menuBarPinnedPorts) as? [String: String]) ?? [:]
        menuBarPinnedValue = string(Key.menuBarPinnedValue).flatMap(PinnedPortValue.init(rawValue:)) ?? .both
        theme = string(Key.theme).flatMap(ThemeSetting.init(rawValue:)) ?? .dark
        backgroundOpacity = min(max(double(Key.backgroundOpacity, 0.88), 0.6), 1)
        glassTint = min(max(double(Key.glassTint, 0.22), 0), 0.5)
        textSize = string(Key.textSize).flatMap(TextSizeSetting.init(rawValue:)) ?? .medium
        animateLinks = bool(Key.animateLinks, true)
        notifyConnect = bool(Key.notifyConnect, true)
        notifyDisconnect = bool(Key.notifyDisconnect, true)
        notifyDowngrade = bool(Key.notifyDowngrade, true)
        notifyCharger = bool(Key.notifyCharger, false)
        notifyDiagnostics = bool(Key.notifyDiagnostics, true)
        powerPollInterval = double(Key.powerPollInterval, 2)
        readSMC = bool(Key.readSMC, true)
        showRawKeys = bool(Key.showRawKeys, false)
        redactExports = bool(Key.redactExports, true)
        demoMode = bool(Key.demoMode, false)
        demoScenario = string(Key.demoScenario).flatMap(DemoScenario.init(rawValue:)) ?? .studioDesk
        keepHistory = bool(Key.keepHistory, true)
        portNames = (defaults.dictionary(forKey: Key.portNames) as? [String: String]) ?? [:]
    }

    /// Restores every setting to its default (port names and menu bar pins included).
    func resetAll() {
        for key in Key.all { defaults.removeObject(forKey: key) }
        let fresh = AppSettings(defaults: defaults)
        showMenuBarItem = fresh.showMenuBarItem
        showDockIconWithWindow = fresh.showDockIconWithWindow
        hideEmptyPorts = fresh.hideEmptyPorts
        portOrder = fresh.portOrder
        popoverLayout = fresh.popoverLayout
        menuBarIcon = fresh.menuBarIcon
        menuBarText = fresh.menuBarText
        menuBarPowerPrecision = fresh.menuBarPowerPrecision
        menuBarPinnedPorts = fresh.menuBarPinnedPorts
        menuBarPinnedValue = fresh.menuBarPinnedValue
        theme = fresh.theme
        backgroundOpacity = fresh.backgroundOpacity
        glassTint = fresh.glassTint
        textSize = fresh.textSize
        animateLinks = fresh.animateLinks
        notifyConnect = fresh.notifyConnect
        notifyDisconnect = fresh.notifyDisconnect
        notifyDowngrade = fresh.notifyDowngrade
        notifyCharger = fresh.notifyCharger
        notifyDiagnostics = fresh.notifyDiagnostics
        powerPollInterval = fresh.powerPollInterval
        readSMC = fresh.readSMC
        showRawKeys = fresh.showRawKeys
        redactExports = fresh.redactExports
        demoMode = fresh.demoMode
        demoScenario = fresh.demoScenario
        keepHistory = fresh.keepHistory
        portNames = fresh.portNames
    }

    enum Key {
        static let showMenuBarItem = "showMenuBarItem"
        static let showDockIconWithWindow = "showDockIconWithWindow"
        static let hideEmptyPorts = "hideEmptyPorts"
        static let portOrder = "portOrder"
        static let popoverLayout = "popoverLayout"
        static let menuBarIcon = "menuBarIcon"
        static let menuBarText = "menuBarText"
        static let menuBarPowerPrecision = "menuBarPowerPrecision"
        static let menuBarPinnedPorts = "menuBarPinnedPorts"
        static let menuBarPinnedValue = "menuBarPinnedValue"
        static let theme = "theme"
        static let backgroundOpacity = "backgroundOpacity"
        static let glassTint = "glassTint"
        static let textSize = "textSize"
        static let animateLinks = "animateLinks"
        static let notifyConnect = "notifyConnect"
        static let notifyDisconnect = "notifyDisconnect"
        static let notifyDowngrade = "notifyDowngrade"
        static let notifyCharger = "notifyCharger"
        static let notifyDiagnostics = "notifyDiagnostics"
        static let powerPollInterval = "powerPollInterval"
        static let readSMC = "readSMC"
        static let showRawKeys = "showRawKeys"
        static let redactExports = "redactExports"
        static let demoMode = "demoMode"
        static let demoScenario = "demoScenario"
        static let keepHistory = "keepHistory"
        static let portNames = "portNames"

        static let all = [
            showMenuBarItem, showDockIconWithWindow, hideEmptyPorts, portOrder, popoverLayout, menuBarIcon,
            menuBarText, menuBarPowerPrecision, menuBarPinnedPorts, menuBarPinnedValue,
            theme, backgroundOpacity, glassTint, textSize, animateLinks, notifyConnect, notifyDisconnect, notifyDowngrade,
            notifyCharger, notifyDiagnostics, powerPollInterval, readSMC, showRawKeys, redactExports, demoMode,
            demoScenario, keepHistory, portNames,
        ]
    }
}
