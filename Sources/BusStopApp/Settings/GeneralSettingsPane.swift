import BusStopCore
import SwiftUI

/// General: launch at login, menu bar and Dock presence, port list options.
struct GeneralSettingsPane: View {
    var store: PortStore

    @State private var launchAtLogin = false
    @State private var launchStatus = ""
    @State private var showLaunchError = false
    @State private var launchErrorMessage = ""

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section("Startup") {
                Toggle("Open Bus Stop at login", isOn: $launchAtLogin)
                SettingsCaption(launchStatus)
                Button("Open Login Items…") {
                    LaunchAtLogin.openSystemSettings()
                }
            }

            Section("Menu bar and Dock") {
                Toggle("Show the menu bar item", isOn: $settings.showMenuBarItem)
                SettingsCaption("When the item is hidden, opening Bus Stop shows the topology window.")
                Toggle("Show the Dock icon while a window is open", isOn: $settings.showDockIconWithWindow)
            }

            Section("Ports") {
                Toggle("Hide empty ports", isOn: $settings.hideEmptyPorts)
                Picker("Port order", selection: $settings.portOrder) {
                    ForEach(PortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
            }
        }
        .settingsPaneStyle()
        .onAppear(perform: syncLaunchState)
        .onChange(of: launchAtLogin) { _, wanted in
            applyLaunchAtLogin(wanted)
        }
        .alert("Could not change the login item", isPresented: $showLaunchError) {
            Button("Open Login Items…") { LaunchAtLogin.openSystemSettings() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchErrorMessage)
        }
    }

    /// On (or waiting for approval) counts as on.
    private var systemLaunchState: Bool {
        LaunchAtLogin.isEnabled || LaunchAtLogin.requiresApproval
    }

    private func syncLaunchState() {
        launchAtLogin = systemLaunchState
        launchStatus = LaunchAtLogin.statusDescription
    }

    private func applyLaunchAtLogin(_ wanted: Bool) {
        guard wanted != systemLaunchState else {
            launchStatus = LaunchAtLogin.statusDescription
            return
        }
        do {
            try LaunchAtLogin.setEnabled(wanted)
        } catch {
            launchErrorMessage = "\(error.localizedDescription)\n\nYou can add Bus Stop in System Settings › General › Login Items instead."
            showLaunchError = true
        }
        syncLaunchState()
    }
}
