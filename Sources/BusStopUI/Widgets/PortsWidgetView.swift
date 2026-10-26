import BusStopCore
import SwiftUI
import WidgetKit

/// The Ports widget: one row per port in physical order, with what is plugged
/// in, its link speed and its power. Extra Large lays the ports out in two
/// columns and adds the devices behind each hub or dock. Tapping a row opens
/// the app with that port selected.
public struct PortsWidgetView: View {
    let entry: WidgetTimeline.Entry
    let family: WidgetFamily

    public init(entry: WidgetTimeline.Entry, family: WidgetFamily) {
        self.entry = entry
        self.family = family
    }

    public var body: some View {
        WidgetChrome("Ports", symbol: "cable.connector", entry: entry) { payload in
            GeometryReader { proxy in
                PortsWidgetContent(snapshot: payload.snapshot, layout: layout(payload, height: proxy.size.height))
            }
        }
        .widgetURL(BusStopLink.page(.allPorts).url)
    }

    var isExtraLarge: Bool { family == .systemExtraLarge }

    func layout(_ payload: WidgetPayload, height: CGFloat) -> PortsWidgetLayout {
        PortsWidgetLayout(ports: payload.snapshot.ports, showsTrees: isExtraLarge,
                          columnCount: isExtraLarge ? 2 : 1, height: height)
    }
}

/// The columns of a fitted layout, top-aligned.
struct PortsWidgetContent: View {
    let snapshot: HostSnapshot
    let layout: PortsWidgetLayout

    var body: some View {
        // Slots for speed and power line up down each column, and are left
        // out when nothing shown has a value for them.
        let slots = PortsWidgetSlots(layout)
        HStack(alignment: .top, spacing: 20) {
            ForEach(layout.columns.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: layout.gap) {
                    ForEach(layout.columns[i], id: \.port.id) { block in
                        Link(destination: BusStopLink.port(block.port.key).url) {
                            PortsWidgetBlock(block: block, slots: slots,
                                             diagnostics: snapshot.diagnostics.filter { $0.portKey == block.port.key })
                        }
                        .buttonStyle(.plain)
                    }
                    if i == layout.columns.count - 1, layout.hiddenPorts > 0 {
                        PortsWidgetMoreLine(text: "+\(PopoverText.count(layout.hiddenPorts, "more port", "more ports"))")
                            .padding(.leading, PortsWidgetSlots.textInset)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// Fixed widths for the trailing values, so they form columns.
struct PortsWidgetSlots {
    static let iconSize: CGFloat = 24
    static let iconSpacing: CGFloat = 8
    /// Where row text starts, after the port icon.
    static var textInset: CGFloat { iconSize + iconSpacing }
    static let indent: CGFloat = 14

    var speed: CGFloat
    var power: CGFloat

    init(_ layout: PortsWidgetLayout) {
        let blocks = layout.columns.flatMap { $0 }
        let ports = blocks.map(\.port)
        let devices = blocks.flatMap(\.tree).map(\.device)
        speed = ports.contains { $0.link != nil } || devices.contains { $0.link != nil } ? 62 : 0
        power = ports.contains { $0.widgetPower != nil } || devices.contains { $0.widgetMilliwatts != nil } ? 58 : 0
    }
}

/// One port's row, its tree and the tree's "+N more" line.
struct PortsWidgetBlock: View {
    let block: PortsWidgetLayout.Block
    let slots: PortsWidgetSlots
    let diagnostics: [Diagnostic]

    var body: some View {
        let port = block.port
        VStack(alignment: .leading, spacing: 0) {
            PortsWidgetRow(port: port, slots: slots, diagnostics: diagnostics)
            ForEach(block.tree.indices, id: \.self) { i in
                PortsWidgetDeviceRow(device: block.tree[i].device, depth: block.tree[i].depth, slots: slots)
            }
            if block.hiddenDevices > 0 {
                let depth = block.tree.last?.depth ?? 1
                PortsWidgetMoreLine(text: "+\(PopoverText.count(block.hiddenDevices, "more device", "more devices"))")
                    .padding(.leading, PortsWidgetSlots.textInset + CGFloat(depth - 1) * PortsWidgetSlots.indent)
            }
        }
        .opacity(port.isConnected ? 1 : 0.62)
    }
}

/// Icon, name and diagnostic mark over what is connected; speed and power on the right.
struct PortsWidgetRow: View {
    let port: PhysicalPort
    let slots: PortsWidgetSlots
    let diagnostics: [Diagnostic]

    var body: some View {
        HStack(spacing: PortsWidgetSlots.iconSpacing) {
            PortIcon(kind: port.kind, isActive: port.isConnected, size: PortsWidgetSlots.iconSize)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(port.label.shortTitle)
                        .lagoonFont(.callout, weight: .semibold)
                        .foregroundStyle(port.isConnected ? Lagoon.textPrimary : Lagoon.textSecondary)
                    if let worst = diagnostics.map(\.severity).max() {
                        Image(systemName: Lagoon.severitySymbol(worst))
                            .lagoonFont(size: 10, weight: .semibold)
                            .foregroundStyle(Lagoon.severityColor(worst))
                    }
                }
                Text(summary)
                    .lagoonFont(.caption)
                    .foregroundStyle(port.isConnected ? Lagoon.textSecondary : Lagoon.textTertiary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            slot(width: slots.speed) {
                if let link = port.link {
                    SpeedChip(link: link).fixedSize().widgetAccentable()
                }
            }
            slot(width: slots.power) {
                if let power = port.widgetPower, let milliwatts = power.milliwatts {
                    PowerBadge(milliwatts: milliwatts, direction: power.direction, isMeasured: power.isMeasured)
                        .fixedSize()
                }
            }
        }
        .frame(height: PortsWidgetLayout.Metrics.portRow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PopoverText.portAccessibilityLabel(port, isPinned: false, speaksLink: true,
                                                               health: diagnostics))
    }

    /// The device, a count, the charger, or "Empty".
    private var summary: String {
        port.isConnected || !port.devices.isEmpty ? PopoverText.compactSummary(port, devices: port.devices) : "Empty"
    }
}

/// A device behind a hub or dock: icon and name, indented by depth, with its
/// speed and allocated power under the port row's.
struct PortsWidgetDeviceRow: View {
    let device: DeviceNode
    let depth: Int
    let slots: PortsWidgetSlots

    var body: some View {
        HStack(spacing: 6) {
            DeviceIcon(kind: device.kind, size: 14)
                .widgetAccentable()
            Text(device.name)
                .lagoonFont(.caption)
                .foregroundStyle(Lagoon.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The chips above pad their text by 7 points; plain values line up with it.
            slot(width: slots.speed) {
                if let rate = device.link?.rateLabel { value(rate) }
            }
            slot(width: slots.power) {
                if let milliwatts = device.widgetMilliwatts { value(Format.power(milliwatts: milliwatts)) }
            }
        }
        .padding(.leading, PortsWidgetSlots.textInset + CGFloat(depth - 1) * PortsWidgetSlots.indent)
        .frame(height: PortsWidgetLayout.Metrics.deviceRow)
        .background(alignment: .leading) { guides }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PopoverText.deviceAccessibilityLabel(device, port: nil, depth: depth, isDeparting: false))
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .lagoonFont(.caption, design: .rounded, monospacedDigits: true)
            .foregroundStyle(Lagoon.textTertiary)
            .lineLimit(1)
            .fixedSize()
            .padding(.trailing, 7)
    }

    /// One hairline per level, under the port icon and each parent's icon.
    private var guides: some View {
        HStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { level in
                Rectangle()
                    .fill(Lagoon.accent.opacity(0.25))
                    .frame(width: 1)
                    .padding(.leading, level == 0 ? PortsWidgetSlots.iconSize / 2 : PortsWidgetSlots.indent / 2)
                    .frame(width: level == 0 ? PortsWidgetSlots.textInset : PortsWidgetSlots.indent, alignment: .leading)
            }
        }
        .widgetAccentable()
    }
}

/// "+3 more devices", "+2 more ports".
struct PortsWidgetMoreLine: View {
    let text: String

    var body: some View {
        Text(text)
            .lagoonFont(.caption, weight: .medium)
            .foregroundStyle(Lagoon.textTertiary)
            .frame(height: PortsWidgetLayout.Metrics.deviceRow)
    }
}

/// A trailing-aligned slot of `width`, or nothing when `width` is 0. It
/// keeps its width when empty, which a frame on an empty view would not.
@ViewBuilder
private func slot(width: CGFloat, @ViewBuilder _ content: () -> some View) -> some View {
    if width > 0 { Color.clear.frame(width: width, height: 1).overlay(alignment: .trailing, content: content) }
}

extension PhysicalPort {
    /// The power the row shows: none at 0 W, as in the app.
    var widgetPower: PortPower? {
        power.flatMap { ($0.milliwatts ?? 0) > 0 ? $0 : nil }
    }
}

extension DeviceNode {
    /// Allocated power, when above 0 W.
    var widgetMilliwatts: Int? {
        power?.allocatedMilliwatts.flatMap { $0 > 0 ? $0 : nil }
    }
}
