import BusStopCore
import SwiftUI

/// Notifications: one toggle per kind of alert, plus the permission state.
struct NotificationsSettingsPane: View {
    var store: PortStore

    @State private var permission = "Checking…"
    @State private var isRequesting = false

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section("Notify me when") {
                Toggle("A device connects", isOn: $settings.notifyConnect)
                Toggle("A device disconnects", isOn: $settings.notifyDisconnect)
                Toggle("A link slows down", isOn: $settings.notifyDowngrade)
                Toggle("A charger connects or disconnects", isOn: $settings.notifyCharger)
                Toggle("A new diagnostic appears", isOn: $settings.notifyDiagnostics)
                SettingsCaption("Alerts name the device, the port and the link, for example “Samsung T9 connected · Left Front · USB 3.2 Gen 2 @ 10 Gb/s”. A dock with many devices produces one grouped alert.")
            }

            Section("Permission") {
                LabeledContent("Status", value: permission)
                Button(requestTitle) {
                    requestPermission()
                }
                .disabled(isRequesting)
                SettingsCaption("If you denied notifications before, turn them on for Bus Stop in System Settings › Notifications.")
            }
        }
        .settingsPaneStyle()
        .task { await refreshPermission() }
    }

    private var requestTitle: String {
        isRequesting ? "Asking…" : "Allow Notifications…"
    }

    private func refreshPermission() async {
        permission = await NotificationManager.shared.authorizationStatusDescription()
    }

    private func requestPermission() {
        isRequesting = true
        Task {
            _ = await NotificationManager.shared.requestAuthorization()
            await refreshPermission()
            isRequesting = false
        }
    }
}
