import BusStopCore
import SwiftUI

/// One physical port (docs/SPEC.md §3.2, item 4): connector icon, title,
/// status ring, transport and power chips, then the nested device tree.
/// Empty ports are dimmed with "Nothing connected".
///
/// "Rename Port…" edits the title in place: Return saves, Escape cancels,
/// and an empty name restores the default label.
struct PortCardView: View {
    var port: PhysicalPort
    var store: PortStore

    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var isNameFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        // Live devices with recently departed ones still in their slots.
        let devices = store.devicesWithGhosts(on: port.key)
        let departingIDs = store.departingIDs
        VStack(alignment: .leading, spacing: 8) {
            header
            chips
            if !devices.isEmpty {
                deviceTree(devices, departingIDs: departingIDs)
            } else if let charger = port.charger {
                chargerLine(charger)
            } else if !port.isConnected {
                Text("Nothing connected")
                    .font(.caption)
                    .foregroundStyle(Lagoon.textTertiary)
                    .padding(.leading, 36)
                    .accessibilityHidden(true)
            }
        }
        .lagoonCard(highlighted: contrast == .increased)
        .opacity(port.isConnected || !devices.isEmpty ? 1 : 0.62)
        .animation(reduceMotion ? nil : DeviceRowTransition.spring,
                   value: Self.animationKey(devices, departingIDs: departingIDs))
        .accessibilityElement(children: .contain)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            PortIcon(kind: port.kind, isActive: port.isConnected)
            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    renameField
                } else {
                    Text(port.label.title)
                        .font(Lagoon.titleFont)
                        .foregroundStyle(port.isConnected ? Lagoon.textPrimary : Lagoon.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if let caption = headerCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Lagoon.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 6)
            StatusRing(isActive: port.isConnected)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename Port\u{2026}") { beginRenaming() }
            if port.label.source == .user {
                Button("Restore Default Name") { store.renamePort(port.key, to: nil) }
            }
            Divider()
            Button("Show in Topology") {
                WindowManager.shared.showTopology(selecting: .port(port.key))
            }
        }
        .accessibilityElement(children: isRenaming ? .contain : .ignore)
        .accessibilityLabel(PopoverText.portAccessibilityLabel(port))
        .accessibilityActions {
            Button("Rename Port") { beginRenaming() }
            Button("Show in Topology") {
                WindowManager.shared.showTopology(selecting: .port(port.key))
            }
        }
    }

    /// Capability text, or the editing hint while renaming.
    private var headerCaption: String? {
        // The field's placeholder shows the default name an empty entry restores.
        if isRenaming { return "Return to save, Esc to cancel" }
        return port.capabilityDescription
    }

    private var renameField: some View {
        TextField("Port name", text: $draftName, prompt: Text(port.label.shortTitle))
            .textFieldStyle(.plain)
            .font(Lagoon.titleFont)
            .foregroundStyle(Lagoon.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Lagoon.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Lagoon.accent.opacity(0.6), lineWidth: 1)
            )
            .focused($isNameFieldFocused)
            .onSubmit { commitRename() }
            .onExitCommand { cancelRename() }
            .onChange(of: isNameFieldFocused) { _, focused in
                // Clicking elsewhere saves, like renaming in Finder.
                if !focused && isRenaming { commitRename() }
            }
            .accessibilityLabel("Port name")
    }

    private func beginRenaming() {
        draftName = port.label.source == .user ? (port.label.location ?? "") : ""
        isRenaming = true
        // Focus after the field exists.
        Task { @MainActor in
            isNameFieldFocused = true
        }
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        store.renamePort(port.key, to: draftName)
    }

    private func cancelRename() {
        isRenaming = false
        isNameFieldFocused = false
    }

    // MARK: Chips

    @ViewBuilder
    private var chips: some View {
        let transports = port.activeTransports.filter { $0.kind != .cc }
        let power = port.power.flatMap { power in (power.milliwatts ?? 0) > 0 ? power : nil }
        if !transports.isEmpty || power != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    transportChips(transports)
                    powerChip(power)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) { transportChips(transports) }
                    powerChip(power)
                }
                VStack(alignment: .leading, spacing: 6) {
                    transportChips(transports)
                    powerChip(power)
                }
            }
            .padding(.leading, 36)
        }
    }

    @ViewBuilder
    private func transportChips(_ transports: [TransportInfo]) -> some View {
        ForEach(transports, id: \.kind) { transport in
            TransportChip(transport: transport)
        }
    }

    @ViewBuilder
    private func powerChip(_ power: PortPower?) -> some View {
        if let power, let milliwatts = power.milliwatts {
            PowerBadge(milliwatts: milliwatts, direction: power.direction, isMeasured: power.isMeasured)
        }
    }

    // MARK: Devices

    private func deviceTree(_ devices: [DeviceNode], departingIDs: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(devices) { device in
                DeviceTreeNode(device: device, depth: 0, port: port, departingIDs: departingIDs)
                    .transition(DeviceRowTransition.make(reduceMotion: reduceMotion))
            }
        }
        .padding(.top, 2)
    }

    private func chargerLine(_ charger: ChargerInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "powerplug.fill")
                .font(.caption)
                .foregroundStyle(Lagoon.powerIn)
            Text(charger.displayName)
                .font(.caption)
                .foregroundStyle(Lagoon.textSecondary)
                .lineLimit(1)
        }
        .padding(.leading, 36)
        .accessibilityHidden(true)
    }

    /// Changes whenever a device arrives, leaves or its ghost expires, to
    /// drive the spring.
    static func animationKey(_ devices: [DeviceNode], departingIDs: Set<String>) -> [String] {
        devices.flatMap { $0.flattened() }.map { entry in
            departingIDs.contains(entry.device.id) ? "departing:" + entry.device.id : entry.device.id
        }
    }
}
