import BusStopCore
import BusStopUI
import SwiftUI

/// Ports: rename each of this Mac's ports, find a port by plugging into it,
/// or reset every name.
struct PortsSettingsPane: View {
    var store: PortStore

    @State private var confirmReset = false
    /// The snapshot from when "Identify a Port" was pressed; nil when not identifying.
    @State private var identifyBaseline: HostSnapshot?
    /// The port that changed since `identifyBaseline`.
    @State private var identifiedKey: PortKey?

    var body: some View {
        let ports = store.snapshot.ports
        Form {
            Section {
                if ports.isEmpty {
                    Text(store.hasLoaded ? "macOS did not report any physical ports." : "Reading ports…")
                        .foregroundStyle(Lagoon.textSecondary)
                } else {
                    ForEach(ports) { port in
                        PortsSettingsRow(store: store, port: port)
                            .listRowBackground(port.key == identifiedKey ? Lagoon.accent.opacity(0.18) : nil)
                    }
                }
            } header: {
                Text("Ports on \(store.snapshot.machine.name)")
            } footer: {
                SettingsCaption("Names are saved for this Mac model. Leave a name empty to use the default from the model catalogue.")
            }

            identifySection

            Section {
                Button("Copy Catalogue Entry") {
                    if let entry = try? PortIdentification.catalogEntry(for: store.snapshot) {
                        PopoverText.copyToPasteboard(entry)
                    }
                }
                .disabled(store.snapshot.isDemo || ports.isEmpty)
            } footer: {
                SettingsCaption("Copies this Mac's port names as a PortScope catalogue entry, for a pull request to the Bus Stop or PortScope catalogue. Nothing is sent.")
            }

            Section {
                Button("Reset Names", role: .destructive) {
                    confirmReset = true
                }
                .disabled(!hasCustomNames(ports))
            }
        }
        .settingsPaneStyle()
        .onChange(of: store.snapshot) { _, snapshot in
            guard let identifyBaseline else { return }
            // Demo and live snapshots share port keys, so a switch would look like a plug.
            guard snapshot.isDemo == identifyBaseline.isDemo else { return stopIdentifying() }
            if let key = identifiedKey {
                if snapshot.port(key) == nil { startIdentifying() }
                return
            }
            let changed = PortIdentification.changedPorts(from: identifyBaseline, to: snapshot)
            if changed.count == 1 {
                identifiedKey = changed[0]
            } else if changed.count > 1 {
                // Several ports changed at once: start over from here rather than guess.
                self.identifyBaseline = snapshot
            }
        }
        .confirmationDialog("Reset every port name?", isPresented: $confirmReset) {
            Button("Reset Names", role: .destructive) { store.resetPortNames() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ports go back to their catalogue or generic names.")
        }
    }

    @ViewBuilder
    private var identifySection: some View {
        Section {
            if let key = identifiedKey, let port = store.snapshot.port(key) {
                HStack(spacing: 12) {
                    PortIcon(kind: port.kind, isActive: true, size: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("That was \(port.label.title) (\(port.registryName)).")
                        PortNameEditor(store: store, port: port)
                    }
                }
                HStack {
                    Button("Identify Another") { startIdentifying() }
                    Button("Done") { stopIdentifying() }
                }
            } else if identifyBaseline != nil {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Plug something into the port you want to name, or unplug it.")
                }
                Button("Cancel") { stopIdentifying() }
            } else {
                Button("Identify a Port…") { startIdentifying() }
                    .disabled(store.snapshot.ports.isEmpty || store.snapshot.isDemo)
            }
        } header: {
            Text("Identify a Port")
        } footer: {
            SettingsCaption("Bus Stop highlights the port whose state changes. Confirm its name, or type where it really is.")
        }
    }

    private func startIdentifying() {
        identifyBaseline = store.snapshot
        identifiedKey = nil
    }

    private func stopIdentifying() {
        identifyBaseline = nil
        identifiedKey = nil
    }

    private func hasCustomNames(_ ports: [PhysicalPort]) -> Bool {
        ports.contains { $0.label.source == .user }
    }
}

/// One port: connector icon, name field and what the port is.
struct PortsSettingsRow: View {
    var store: PortStore
    var port: PhysicalPort

    var body: some View {
        HStack(spacing: 12) {
            PortIcon(kind: port.kind, isActive: port.isConnected, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                PortNameEditor(store: store, port: port)
                Text(detail)
                    .lagoonFont(.caption)
                    .foregroundStyle(Lagoon.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts = [port.kind.displayName, "\(port.registryName)"]
        if let capability = port.capabilityDescription { parts.append(capability) }
        parts.append(port.isConnected ? "In use" : "Empty")
        return parts.joined(separator: " · ")
    }
}
