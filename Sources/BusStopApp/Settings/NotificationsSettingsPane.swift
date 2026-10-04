import AppKit
import BusStopCore
import SwiftUI
import UserNotifications

/// Notifications: one toggle per kind of alert, plus the permission state.
///
/// The permission can change in System Settings while this pane is open, so
/// it is read again whenever the window or the app becomes active.
struct NotificationsSettingsPane: View {
    var store: PortStore

    /// nil until the first read, and outside the app bundle.
    @State private var status: NotificationManager.Authorization?
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
                LabeledContent("Status", value: statusText)
                permissionAction
            }
        }
        .settingsPaneStyle()
        .task { await refreshPermission() }
        .background {
            HostingWindowObserver(onActivate: {
                Task { await refreshPermission() }
            })
        }
    }

    private var statusText: String {
        guard NotificationManager.shared.isAvailable else { return "Unavailable outside the app bundle" }
        switch status {
        case .allowed?: return "Allowed"
        case .denied?: return "Denied"
        case .notDetermined?: return "Not requested"
        case nil: return "Checking…"
        }
    }

    /// What the user can do in each state: ask, or go to System Settings.
    @ViewBuilder
    private var permissionAction: some View {
        switch status {
        case .notDetermined?:
            Button(isRequesting ? "Asking…" : "Allow Notifications…") {
                requestPermission()
            }
            .disabled(isRequesting)
        case .denied?:
            Button("Open Notification Settings…", action: Self.openNotificationSettings)
            SettingsCaption("Notifications are off for Bus Stop. Turn them on in System Settings › Notifications › Bus Stop.")
        case .allowed?:
            SettingsCaption("Bus Stop can post alerts. Change their style in System Settings › Notifications › Bus Stop.")
        case nil:
            if !NotificationManager.shared.isAvailable {
                SettingsCaption("Notifications work when Bus Stop runs as an app, not as a bare binary.")
            }
        }
    }

    private func refreshPermission() async {
        guard NotificationManager.shared.isAvailable else {
            status = nil
            return
        }
        status = await Self.currentAuthorization()
    }

    private func requestPermission() {
        isRequesting = true
        Task {
            _ = await NotificationManager.shared.requestAuthorization()
            await refreshPermission()
            isRequesting = false
        }
    }

    /// The authorization state, read off the main actor; only the Sendable
    /// result crosses back (as in `NotificationManager`).
    nonisolated private static func currentAuthorization() async -> NotificationManager.Authorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    /// System Settings › Notifications, on Bus Stop's page when possible.
    private static func openNotificationSettings() {
        let base = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        let target = Bundle.main.bundleIdentifier.map { "\(base)?id=\($0)" } ?? base
        if let url = URL(string: target) ?? URL(string: base) {
            NSWorkspace.shared.open(url)
        }
    }
}
