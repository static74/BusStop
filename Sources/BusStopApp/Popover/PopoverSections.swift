import BusStopCore
import SwiftUI

/// Devices that could not be tied to a port.
struct OtherDevicesSection: View {
    var store: PortStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let devices = store.snapshot.otherDevices
        let departing = store.departing(on: nil)
        if !devices.isEmpty || !departing.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Other devices",
                              trailing: PopoverText.count(devices.reduce(0) { $0 + 1 + $1.descendantCount },
                                                          "device", "devices"))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(devices) { device in
                        DeviceTreeNode(device: device, depth: 0, port: nil)
                            .transition(DeviceRowTransition.make(reduceMotion: reduceMotion))
                    }
                    ForEach(departing) { entry in
                        DeviceRowView(device: entry.device, depth: 0, port: nil, isDeparting: true)
                            .transition(.opacity)
                    }
                }
                .lagoonCard()
                .animation(reduceMotion ? nil : DeviceRowTransition.spring,
                           value: devices.map(\.id) + departing.map(\.id))
            }
        }
    }
}

/// Compact list of external displays with the port each one uses.
struct DisplaysSection: View {
    var store: PortStore

    var body: some View {
        let snapshot = store.snapshot
        let displays = snapshot.displays.filter { !$0.isBuiltin }
        if !displays.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Displays", trailing: PopoverText.count(displays.count, "display", "displays"))
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(displays) { display in
                        DisplayRow(display: display, port: display.portKey.flatMap { snapshot.port($0) })
                    }
                }
                .lagoonCard()
            }
        }
    }
}

private struct DisplayRow: View {
    var display: DisplayInfo
    var port: PhysicalPort?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            DeviceIcon(kind: .display, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Lagoon.textPrimary)
                    .lineLimit(1)
                Text(caption)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Lagoon.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let link = display.link {
                SpeedChip(link: link)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show in Topology") {
                WindowManager.shared.showTopology(selecting: .display(display.id))
            }
            Button("Copy Name") {
                PopoverText.copyToPasteboard(display.name)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// "Left Rear · 5120 × 2880 @ 120 Hz".
    private var caption: String {
        var parts = [port?.label.shortTitle ?? "Port unknown"]
        if let mode = display.modeDescription { parts.append(mode) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var accessibilityLabel: String {
        var parts = ["Display \(display.name)"]
        if let port { parts.append("on \(PopoverText.spokenPortTitle(port.label)) port") }
        if let mode = display.modeDescription { parts.append(mode.replacingOccurrences(of: " × ", with: " by ")) }
        return parts.joined(separator: ", ")
    }
}
