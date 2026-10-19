import BusStopCore
import SwiftUI

/// The compact popover's port list (docs/SPEC.md §3.2): one card with a line
/// per port. Draws nothing when `ports` is empty; the popover shows its own
/// "Nothing is connected" note then.
struct CompactPortList: View {
    var ports: [PhysicalPort]
    var store: PortStore

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if !ports.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ports) { port in
                    if port.id != ports.first?.id { Hairline() }
                    CompactPortRow(port: port, store: store)
                }
            }
            .lagoonCard(highlighted: contrast == .increased)
        }
    }
}

/// One line per port for the compact popover: icon, short name, what is
/// connected, speed and power. The disclosure shows the same device tree as
/// the card, and the context menu and VoiceOver actions match the card's.
struct CompactPortRow: View {
    var port: PhysicalPort
    var store: PortStore

    @State private var isExpanded = false
    @State private var isRenaming: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `isRenaming` starts the row with its name field open (for tests).
    init(port: PhysicalPort, store: PortStore, isRenaming: Bool = false) {
        self.port = port
        self.store = store
        _isRenaming = State(initialValue: isRenaming)
    }

    var body: some View {
        // Live devices with recently departed ones still in their slots.
        let devices = store.devicesWithGhosts(on: port.key)
        let departingIDs = store.departingIDs
        VStack(alignment: .leading, spacing: 4) {
            line(devices)
            if isExpanded && !devices.isEmpty {
                PortDeviceTree(port: port, devices: devices, departingIDs: departingIDs)
            }
        }
        .opacity(port.isConnected || !devices.isEmpty ? 1 : 0.62)
        .animation(reduceMotion ? nil : DeviceRowTransition.spring,
                   value: PortCardView.animationKey(devices, departingIDs: departingIDs))
        .accessibilityElement(children: .contain)
    }

    private func line(_ devices: [DeviceNode]) -> some View {
        let isPinned = store.pinnedPortKey == port.key
        let power = port.power.flatMap { power in (power.milliwatts ?? 0) > 0 ? power : nil }
        return HStack(alignment: .center, spacing: 8) {
            chevron(hasDevices: !devices.isEmpty)
            PortIcon(kind: port.kind, isActive: port.isConnected, size: 18)
            if isRenaming {
                PortRenameField(port: port, store: store, isRenaming: $isRenaming)
                    .layoutPriority(1)
            } else {
                HStack(spacing: 4) {
                    Text(port.label.shortTitle)
                        .lagoonFont(.callout, weight: .semibold)
                        .foregroundStyle(port.isConnected ? Lagoon.textPrimary : Lagoon.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .lagoonFont(.caption)
                            .foregroundStyle(Lagoon.accent)
                            .accessibilityHidden(true)
                    }
                }
                .layoutPriority(1)
            }
            // The editing hint takes the summary's place while renaming.
            Text(isRenaming ? "Return to save, Esc to cancel" : PopoverText.compactSummary(port, devices: devices))
                .lagoonFont(.caption)
                .foregroundStyle(Lagoon.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let link = port.link {
                SpeedChip(link: link)
                    .fixedSize()
            }
            if let power, let milliwatts = power.milliwatts {
                PowerBadge(milliwatts: milliwatts, direction: power.direction, isMeasured: power.isMeasured)
                    .fixedSize()
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: isRenaming ? .contain : .ignore)
        .accessibilityLabel(PopoverText.portAccessibilityLabel(port, isPinned: isPinned))
        .portActions(port, store: store, rename: { isRenaming = true })
        .accessibilityActions {
            if !devices.isEmpty {
                Button(isExpanded ? "Hide Devices" : "Show Devices", action: toggle)
            }
        }
    }

    @ViewBuilder
    private func chevron(hasDevices: Bool) -> some View {
        if hasDevices {
            Button(action: toggle) {
                Image(systemName: "chevron.right")
                    .lagoonFont(size: 10, weight: .bold)
                    .foregroundStyle(Lagoon.accent.opacity(0.8))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: DeviceRowMetrics.chevronWidth, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Hide devices" : "Show devices")
            .accessibilityHidden(true)
        } else {
            // Keeps names aligned with rows that have a chevron.
            Color.clear.frame(width: DeviceRowMetrics.chevronWidth, height: 1)
        }
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : DeviceRowTransition.spring) {
            isExpanded.toggle()
        }
    }
}
