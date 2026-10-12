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

/// Root view of the settings window: one tab per `SettingsTab`, each a
/// grouped form. Changes apply immediately, including Text Size, which
/// rescales this window too.
struct SettingsView: View {
    var store: PortStore
    var initialTab: SettingsTab = .general

    /// The tab the user picked; nil until they pick one, so `initialTab` wins.
    @State private var chosenTab: SettingsTab? = nil

    var body: some View {
        TabView(selection: selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                pane(for: tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbolName) }
                    .tag(tab)
            }
        }
        .frame(width: 620, height: 500)
        .background(Lagoon.background)
        .preferredColorScheme(.dark)
        .tint(Lagoon.accent)
        .lagoonFont(.body)
        .lagoonTextScale(store.settings.textSize)
        .onChange(of: initialTab) { chosenTab = nil }
    }

    private var selectedTab: Binding<SettingsTab> {
        Binding(
            get: { chosenTab ?? initialTab },
            set: { chosenTab = $0 }
        )
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
    /// Shared look for settings panes: grouped form on true black.
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
