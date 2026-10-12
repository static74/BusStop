import BusStopCore
import SwiftUI

/// Ports: rename each of this Mac's ports, or reset every name.
struct PortsSettingsPane: View {
    var store: PortStore

    @State private var confirmReset = false

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
                    }
                }
            } header: {
                Text("Ports on \(store.snapshot.machine.name)")
            } footer: {
                SettingsCaption("Names are saved for this Mac model. Leave a name empty to use the default from the model catalogue.")
            }

            Section {
                Button("Reset Names", role: .destructive) {
                    confirmReset = true
                }
                .disabled(!hasCustomNames(ports))
            }
        }
        .settingsPaneStyle()
        .confirmationDialog("Reset every port name?", isPresented: $confirmReset) {
            Button("Reset Names", role: .destructive) { store.resetPortNames() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ports go back to their catalogue or generic names.")
        }
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
