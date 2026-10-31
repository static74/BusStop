import BusStopCore
import BusStopUI
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

/// One settings pane with the window's shared environment: each tab of
/// `SettingsTabViewController` hosts one. Changes apply immediately,
/// including Text Size, which rescales the pane too.
struct SettingsPaneRoot: View {
    var store: PortStore
    var tab: SettingsTab

    /// Every pane's size, so switching tabs does not resize the window.
    static let size = CGSize(width: 620, height: 460)

    var body: some View {
        pane(for: tab)
            .frame(width: Self.size.width, height: Self.size.height)
            .background(Lagoon.background)
            .tint(Lagoon.accent)
            .lagoonFont(.body)
            .lagoonTextScale(store.settings.textSize)
            .dataPalette()
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsPane(store: store)
        case .menuBar: MenuBarSettingsPane(store: store)
        case .appearance: AppearanceSettingsPane(store: store)
        case .notifications: NotificationsSettingsPane(store: store)
        case .ports: PortsSettingsPane(store: store)
        case .advanced: AdvancedSettingsPane(store: store)
        }
    }
}

extension View {
    /// Shared look for settings panes: grouped form on the Lagoon background.
    func settingsPaneStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Lagoon.background)
    }
}

/// Secondary explanatory text under a settings control.
struct SettingsCaption: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .lagoonFont(.caption)
            .foregroundStyle(Lagoon.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
