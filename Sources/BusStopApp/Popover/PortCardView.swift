import BusStopCore
import BusStopUI
import SwiftUI

/// One physical port (docs/SPEC.md §3.2, item 4): connector icon, title,
/// status ring, transport and power chips, then the nested device tree.
/// Empty ports are dimmed with "Nothing connected".
///
/// "Rename Port…" edits the title in place: Return saves, Escape cancels,
/// and an empty name restores the default label. A pin follows the title of
/// the port pinned to the menu bar, and a health mark the title of a port
/// with a connection-health finding.
struct PortCardView: View {
    var port: PhysicalPort
    var store: PortStore

    @State private var isRenaming = false
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
                PortDeviceTree(port: port, devices: devices, departingIDs: departingIDs)
            } else if let charger = port.charger {
                chargerLine(charger)
            } else if !port.isConnected {
                Text("Nothing connected")
                    .lagoonFont(.caption)
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
        let isPinned = store.pinnedPortKey == port.key
        let health = PopoverText.health(of: port, in: store.snapshot.diagnostics)
        return HStack(alignment: .center, spacing: 10) {
            PortIcon(kind: port.kind, isActive: port.isConnected)
            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    PortRenameField(port: port, store: store, isRenaming: $isRenaming)
                } else {
                    HStack(spacing: 5) {
                        Text(port.label.title)
                            .lagoonFont(.headline, weight: .semibold)
                            .foregroundStyle(port.isConnected ? Lagoon.textPrimary : Lagoon.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .lagoonFont(.caption)
                                .foregroundStyle(Lagoon.accent)
                                .accessibilityHidden(true)
                        }
                        PortHealthMark(findings: health)
                    }
                }
                if let caption = headerCaption {
                    Text(caption)
                        .lagoonFont(.caption)
                        .foregroundStyle(Lagoon.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 6)
            StatusRing(isActive: port.isConnected)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: isRenaming ? .contain : .ignore)
        .accessibilityLabel(PopoverText.portAccessibilityLabel(port, isPinned: isPinned, health: health))
        .portActions(port, store: store, rename: { isRenaming = true })
    }

    /// Capability text, or the editing hint while renaming.
    private var headerCaption: String? {
        // The field's placeholder shows the default name an empty entry restores.
        if isRenaming { return "Return to save, Esc to cancel" }
        return port.capabilityDescription
    }

    // MARK: Chips

    @ViewBuilder
    private var chips: some View {
        let transports = port.activeTransports.filter { $0.kind != .cc }
        let power = port.shownPower
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

    private func chargerLine(_ charger: ChargerInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "powerplug.fill")
                .lagoonFont(.caption)
                .foregroundStyle(Lagoon.powerIn)
            Text(charger.displayName)
                .lagoonFont(.caption)
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

/// In-place port name field for the card and the compact row: Return saves,
/// Escape cancels, clicking away saves, and an empty name restores the
/// default label. Seeds its draft and takes focus when it appears.
struct PortRenameField: View {
    var port: PhysicalPort
    var store: PortStore
    @Binding var isRenaming: Bool

    @State private var draftName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Port name", text: $draftName, prompt: Text(port.label.shortTitle))
            .textFieldStyle(.plain)
            .lagoonFont(.headline, weight: .semibold)
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
            .focused($isFocused)
            .onSubmit { commit() }
            .onExitCommand { cancel() }
            .onChange(of: isFocused) { _, focused in
                // Clicking elsewhere saves, like renaming in Finder.
                if !focused && isRenaming { commit() }
            }
            // The compact rows are rebuilt when the popover closes; save rather than drop the typed name.
            .onDisappear { commit() }
            .onAppear {
                draftName = port.label.source == .user ? (port.label.location ?? "") : ""
                // Focus after the field exists.
                Task { @MainActor in
                    isFocused = true
                }
            }
            .accessibilityLabel("Port name")
    }

    private func commit() {
        guard isRenaming else { return }
        isRenaming = false
        store.renamePort(port.key, to: draftName)
    }

    private func cancel() {
        isRenaming = false
        isFocused = false
    }
}

/// A port's device trees, with devices that just left still in their slots
/// (see `PortStore.devicesWithGhosts(on:)`), sliding in and fading out.
struct PortDeviceTree: View {
    var port: PhysicalPort
    var devices: [DeviceNode]
    var departingIDs: Set<String>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(devices) { device in
                DeviceTreeNode(device: device, depth: 0, port: port, departingIDs: departingIDs)
                    .transition(DeviceRowTransition.make(reduceMotion: reduceMotion))
            }
        }
        .padding(.top, 2)
    }
}

extension View {
    /// A port's context menu and the matching VoiceOver actions: Rename,
    /// Restore Default Name, Show in Topology, and Pin to or Unpin from the
    /// menu bar.
    func portActions(_ port: PhysicalPort, store: PortStore, rename: @escaping () -> Void) -> some View {
        let isPinned = store.pinnedPortKey == port.key
        let pinTitle = isPinned ? "Unpin from Menu Bar" : "Pin to Menu Bar"
        let togglePin = { store.pinPort(isPinned ? nil : port.key) }
        let showInTopology = { WindowManager.shared.showTopology(selecting: .port(port.key)) }
        return contextMenu {
            Button("Rename Port\u{2026}", action: rename)
            if port.label.source == .user {
                Button("Restore Default Name") { store.renamePort(port.key, to: nil) }
            }
            Divider()
            Button(pinTitle, action: togglePin)
            Button("Show in Topology", action: showInTopology)
        }
        .accessibilityActions {
            Button("Rename Port", action: rename)
            if port.label.source == .user {
                Button("Restore Default Name") { store.renamePort(port.key, to: nil) }
            }
            Button(pinTitle, action: togglePin)
            Button("Show in Topology", action: showInTopology)
        }
    }
}

/// A small mark after a port's name when its connections have a health
/// finding (a flaky connection, a flapping or slower link, or a port that
/// stands out); its tooltip lists them. The port's VoiceOver label says the
/// same, so the mark itself is hidden.
struct PortHealthMark: View {
    var findings: [Diagnostic]

    var body: some View {
        if let worst = findings.map(\.severity).max() {
            Image(systemName: "waveform.path.ecg")
                .lagoonFont(.caption, weight: .semibold)
                .foregroundStyle(Lagoon.severityColor(worst))
                .help(findings.map(\.title).joined(separator: "\n"))
                .accessibilityHidden(true)
        }
    }
}

extension PhysicalPort {
    /// The power the card and the compact row show: none at 0 W.
    var shownPower: PortPower? {
        power.flatMap { ($0.milliwatts ?? 0) > 0 ? $0 : nil }
    }
}
