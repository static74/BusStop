import BusStopCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case appearance
    case notifications
    case ports
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .menuBar: return "Menu Bar"
        case .appearance: return "Appearance"
        case .notifications: return "Notifications"
        case .ports: return "Ports"
        case .advanced: return "Advanced"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .appearance: return "paintpalette"
        case .notifications: return "bell.badge"
        case .ports: return "cable.connector"
        case .advanced: return "slider.horizontal.3"
        }
    }
}

/// Root view of the settings window. Placeholder; implemented by the window UI.
struct SettingsView: View {
    var store: PortStore
    var initialTab: SettingsTab = .general

    var body: some View {
        Text("Settings")
            .frame(width: 560, height: 420)
    }
}
