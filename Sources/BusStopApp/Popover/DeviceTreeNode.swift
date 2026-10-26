import BusStopCore
import BusStopUI
import SwiftUI

/// A device and, when expanded, its children, recursively. Containers
/// (hubs, docks, displays with hubs) start expanded.
///
/// Feed it `PortStore.devicesWithGhosts(on:)` and `PortStore.departingIDs`:
/// a device that just left stays in its slot as a dimmed "Disconnected" row,
/// together with everything that left with it.
struct DeviceTreeNode: View {
    var device: DeviceNode
    var depth: Int
    var port: PhysicalPort?
    /// Devices that just left (see `PortStore.departingIDs`).
    var departingIDs: Set<String> = []
    /// True when an ancestor left, so this device left with it.
    var isInsideGhost: Bool = false

    @State private var isExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isDeparting = isInsideGhost || departingIDs.contains(device.id)
        VStack(alignment: .leading, spacing: 0) {
            if isDeparting {
                DeviceRowView(device: device, depth: depth, port: port, isDeparting: true)
            } else {
                DeviceRowView(device: device, depth: depth, port: port, isExpanded: isExpanded,
                              onToggle: toggleAction)
                    .deviceContextMenu(device: device, port: port)
            }
            if isExpanded {
                ForEach(device.children) { child in
                    DeviceTreeNode(device: child, depth: depth + 1, port: port, departingIDs: departingIDs,
                                   isInsideGhost: isDeparting)
                        .transition(DeviceRowTransition.make(reduceMotion: reduceMotion))
                }
            }
        }
    }

    /// Nil for leaf devices, so their rows show no chevron.
    private var toggleAction: (() -> Void)? {
        guard !device.children.isEmpty else { return nil }
        return { toggle() }
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : DeviceRowTransition.spring) {
            isExpanded.toggle()
        }
    }
}

extension View {
    /// "Show in Topology", "Copy Name", "Copy Details".
    func deviceContextMenu(device: DeviceNode, port: PhysicalPort?) -> some View {
        contextMenu {
            Button("Show in Topology") {
                WindowManager.shared.showTopology(selecting: .device(device.id))
            }
            Divider()
            Button("Copy Name") {
                PopoverText.copyToPasteboard(device.name)
            }
            Button("Copy Details") {
                let redact = AppSettings.shared.redactExports
                PopoverText.copyToPasteboard(PopoverText.details(for: device, port: port, redactSerials: redact))
            }
        }
    }
}
