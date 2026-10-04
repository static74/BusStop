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

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .extraLarge: return .xLarge
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

    // MARK: Menu bar

    var menuBarIcon: MenuBarIconStyle { didSet { defaults.set(menuBarIcon.rawValue, forKey: Key.menuBarIcon) } }
    var menuBarText: MenuBarTextMode { didSet { defaults.set(menuBarText.rawValue, forKey: Key.menuBarText) } }
    var menuBarPowerPrecision: PowerPrecision {
        didSet { defaults.set(menuBarPowerPrecision.rawValue, forKey: Key.menuBarPowerPrecision) }
    }

    // MARK: Appearance

    /// Opacity of the black backing behind popover and window content (0.6…1).
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
        menuBarIcon = string(Key.menuBarIcon).flatMap(MenuBarIconStyle.init(rawValue:)) ?? .busStop
        menuBarText = string(Key.menuBarText).flatMap(MenuBarTextMode.init(rawValue:)) ?? .power
        menuBarPowerPrecision = string(Key.menuBarPowerPrecision).flatMap(PowerPrecision.init(rawValue:)) ?? .automatic
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
        portNames = (defaults.dictionary(forKey: Key.portNames) as? [String: String]) ?? [:]
    }

    /// Restores every setting to its default (port names included).
    func resetAll() {
        for key in Key.all { defaults.removeObject(forKey: key) }
        let fresh = AppSettings(defaults: defaults)
        showMenuBarItem = fresh.showMenuBarItem
        showDockIconWithWindow = fresh.showDockIconWithWindow
        hideEmptyPorts = fresh.hideEmptyPorts
        portOrder = fresh.portOrder
        menuBarIcon = fresh.menuBarIcon
        menuBarText = fresh.menuBarText
        menuBarPowerPrecision = fresh.menuBarPowerPrecision
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
        portNames = fresh.portNames
    }

    enum Key {
        static let showMenuBarItem = "showMenuBarItem"
        static let showDockIconWithWindow = "showDockIconWithWindow"
        static let hideEmptyPorts = "hideEmptyPorts"
        static let portOrder = "portOrder"
        static let menuBarIcon = "menuBarIcon"
        static let menuBarText = "menuBarText"
        static let menuBarPowerPrecision = "menuBarPowerPrecision"
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
        static let portNames = "portNames"

        static let all = [
            showMenuBarItem, showDockIconWithWindow, hideEmptyPorts, portOrder, menuBarIcon, menuBarText,
            menuBarPowerPrecision,
            backgroundOpacity, glassTint, textSize, animateLinks, notifyConnect, notifyDisconnect, notifyDowngrade,
            notifyCharger, notifyDiagnostics, powerPollInterval, readSMC, showRawKeys, redactExports, demoMode,
            demoScenario, portNames,
        ]
    }
}
