import BusStopCore
import SwiftUI

/// Advanced: data collection, raw keys, exports, demo mode and resets.
struct AdvancedSettingsPane: View {
    var store: PortStore

    @State private var confirmReset = false

    /// The project page. A literal, so it always parses.
    private static let projectURL = URL(string: "https://github.com/static74/BusStop")!

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section("Data") {
                Picker("Power refresh", selection: $settings.powerPollInterval) {
                    Text("Every second").tag(1.0)
                    Text("Every 2 seconds").tag(2.0)
                    Text("Every 5 seconds").tag(5.0)
                }
                SettingsCaption("How often power figures update while a Bus Stop window or the popover is open. In the background Bus Stop checks every 10 seconds.")
                Toggle("Read live port power from the SMC", isOn: $settings.readSMC)
                SettingsCaption("The most accurate per-port output figure on many Macs. Turn it off if you prefer Bus Stop to use only documented sources.")
            }

            Section("Inspector") {
                Toggle("Show raw IORegistry keys", isOn: $settings.showRawKeys)
                SettingsCaption("Adds every registry property of the selected port or device to the inspector, for troubleshooting.")
            }

            Section("Export") {
                Toggle("Redact serial numbers in exports", isOn: $settings.redactExports)
                ForEach(ExportKind.allCases) { kind in
                    Button(kind.title) {
                        ExportController.export(kind, store: store)
                    }
                }
            }

            Section("Demo mode") {
                Toggle("Show a demo setup instead of this Mac", isOn: $settings.demoMode)
                Picker("Scenario", selection: $settings.demoScenario) {
                    ForEach(DemoScenario.allCases) { scenario in
                        Text(scenario.title).tag(scenario)
                    }
                }
                .disabled(!settings.demoMode)
                SettingsCaption("Useful for screenshots and for trying Bus Stop without accessories. A DEMO badge shows while it is on.")
            }

            Section("Reset") {
                Button("Reset All Settings…", role: .destructive) {
                    confirmReset = true
                }
            }

            Section("About") {
                Link(destination: Self.projectURL) {
                    Label("Project page on GitHub", systemImage: "arrow.up.right.square")
                }
                Button("About Bus Stop") {
                    WindowManager.shared.showAbout()
                }
            }
        }
        .settingsPaneStyle()
        .onChange(of: settings.demoMode) { store.applySettings() }
        .onChange(of: settings.demoScenario) { store.applySettings() }
        .onChange(of: settings.powerPollInterval) { store.applySettings() }
        .onChange(of: settings.readSMC) { store.applySettings() }
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset All Settings", role: .destructive) {
                store.settings.resetAll()
                store.applySettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every preference returns to its default, including port names.")
        }
    }
}
