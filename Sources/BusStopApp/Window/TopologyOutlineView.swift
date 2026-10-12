import BusStopCore
import SwiftUI

/// Overview's List mode: each port followed by its device tree, with
/// indentation guides, collapsible hubs and fading departing devices.
///
/// The tree is flattened into rows so every row is directly selectable and
/// containers start expanded.
struct TopologyOutlineView: View {
    var store: PortStore
    var ports: [PhysicalPort]
    var includeOther: Bool
    var searchText: String
    /// A row to scroll into view; cleared once handled.
    @Binding var scrollRequest: TopologyScrollRequest?

    /// Row IDs of collapsed containers (everything starts expanded).
    @State private var collapsed: Set<String> = []
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let sections = makeSections()
        Group {
            if sections.isEmpty {
                PortListEmptyView(state: PortListEmptyState.resolve(searchText: searchText, store: store), store: store)
                    .onChange(of: scrollRequest, initial: true) { _, request in
                        if request != nil { scrollRequest = nil }
                    }
            } else {
                ScrollViewReader { proxy in
                    list(sections)
                        .onChange(of: scrollRequest, initial: true) { _, request in
                            guard let request else { return }
                            scrollRequest = nil
                            scroll(to: request, proxy: proxy)
                        }
                }
            }
        }
    }

    private func list(_ sections: [TopologyOutlineSection]) -> some View {
        List(selection: selection) {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        rowView(row)
                            .id(row.id)
                            .tag(row.id)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.disabled)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: sections.map(\.signature))
    }

    /// Expands the hubs above the requested device, then scrolls to its row.
    private func scroll(to request: TopologyScrollRequest, proxy: ScrollViewProxy) {
        guard let tag = request.tag else { return }
        if case .device(let id)? = SelectionTag.selection(for: tag) {
            let trees = ports.map(\.devices) + [store.snapshot.otherDevices]
            for devices in trees {
                guard let path = Self.ancestors(of: id, in: devices) else { continue }
                collapsed.subtract(path.map(SelectionTag.device))
                break
            }
        }
        // On the next turn, once expanded rows exist.
        Task { @MainActor in
            withAnimation(.snappy) { proxy.scrollTo(tag, anchor: .center) }
        }
    }

    /// IDs of the devices above `id`, outermost first, or nil when `id` is not in `devices`.
    static func ancestors(of id: String, in devices: [DeviceNode]) -> [String]? {
        for device in devices {
            if device.id == id { return [] }
            if let below = ancestors(of: id, in: device.children) { return [device.id] + below }
        }
        return nil
    }

    // MARK: Selection

    private var selection: Binding<String?> {
        Binding(
            get: { SelectionTag.string(for: store.selection) },
            set: { tag in
                if let selection = SelectionTag.selection(for: tag) { store.selection = selection }
            }
        )
    }

    private func toggle(_ id: String) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func rowView(_ row: TopologyOutlineRow) -> some View {
        switch row.kind {
        case .port(let port):
            OutlinePortRow(port: port)
        case .device(let device, let depth, let isDeparting):
            OutlineDeviceRow(
                device: device,
                depth: depth,
                isDeparting: isDeparting,
                isExpanded: !collapsed.contains(row.id),
                onToggle: { toggle(row.id) }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
            .selectionDisabled(isDeparting)
        case .display(let display, let depth):
            OutlineDisplayRow(display: display, depth: depth)
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 12))
        case .otherHeader(let count):
            OutlineOtherRow(count: count)
        case .note(let text):
            Text(text)
                .lagoonFont(.caption)
                .foregroundStyle(WindowContrast.tertiary(contrast))
                .padding(.leading, 44)
                .selectionDisabled()
        }
    }

    // MARK: Model

    private func makeSections() -> [TopologyOutlineSection] {
        let snapshot = store.snapshot
        let query = TopologySearch.normalized(searchText)
        let portDisplays = TopologyExtras.portDisplays(in: snapshot, ports: ports)
        var builder = TopologyOutlineBuilder(collapsed: collapsed)
        var sections: [TopologyOutlineSection] = []

        for port in ports {
            let portMatches = TopologySearch.port(port, matches: query)
            let devices = portMatches ? port.devices : port.devices.compactMap { TopologySearch.prune($0, query: query) }
            let displays = (portDisplays[port.key] ?? []).filter { portMatches || TopologySearch.display($0, matches: query) }
            let departing = store.departing(on: port.key).map(\.device)
            guard portMatches || !devices.isEmpty || !displays.isEmpty else { continue }

            var rows = [TopologyOutlineRow(id: builder.unique(SelectionTag.port(port.key)), kind: .port(port))]
            builder.append(devices: devices, displays: displays, departing: departing, into: &rows)
            if devices.isEmpty && displays.isEmpty && departing.isEmpty {
                rows.append(TopologyOutlineRow(id: builder.unique("note:\(port.key)"),
                                       kind: .note(port.isConnected ? "No data devices" : "Nothing connected")))
            }
            sections.append(TopologyOutlineSection(id: "section:\(port.key)", rows: rows))
        }

        if includeOther {
            let devices = snapshot.otherDevices.compactMap { TopologySearch.prune($0, query: query) }
            let displays = TopologyExtras.otherDisplays(in: snapshot).filter { TopologySearch.display($0, matches: query) }
            let departing = query.isEmpty ? store.departing(on: nil).map(\.device) : []
            if !devices.isEmpty || !displays.isEmpty || !departing.isEmpty {
                let count = devices.reduce(0) { $0 + 1 + $1.descendantCount } + displays.count
                var rows = [TopologyOutlineRow(id: builder.unique("other"), kind: .otherHeader(count: count))]
                builder.append(devices: devices, displays: displays, departing: departing, into: &rows)
                sections.append(TopologyOutlineSection(id: "section:other", rows: rows))
            }
        }
        return sections
    }
}

/// One flattened row.
struct TopologyOutlineRow: Identifiable {
    enum Kind {
        case port(PhysicalPort)
        case device(DeviceNode, depth: Int, isDeparting: Bool)
        case display(DisplayInfo, depth: Int)
        case otherHeader(count: Int)
        case note(String)
    }

    /// The selection tag for selectable rows, otherwise a unique ID.
    var id: String
    var kind: Kind
}

/// A port (or the Other group) and its rows.
struct TopologyOutlineSection: Identifiable {
    var id: String
    var rows: [TopologyOutlineRow]

    /// Changes when rows are added or removed (drives the insert animation).
    var signature: String { rows.map(\.id).joined(separator: "|") }
}

/// Flattens device trees into rows, skipping collapsed branches.
struct TopologyOutlineBuilder {
    var collapsed: Set<String>
    private var used: Set<String> = []

    init(collapsed: Set<String>) {
        self.collapsed = collapsed
    }

    /// A row ID that has not been used yet (devices can repeat in odd captures).
    mutating func unique(_ base: String) -> String {
        var candidate = base
        var counter = 2
        while used.contains(candidate) {
            candidate = "\(base)#\(counter)"
            counter += 1
        }
        used.insert(candidate)
        return candidate
    }

    mutating func append(devices: [DeviceNode], displays: [DisplayInfo], departing: [DeviceNode],
                         into rows: inout [TopologyOutlineRow]) {
        for device in devices { append(device, depth: 0, into: &rows) }
        for display in displays {
            rows.append(TopologyOutlineRow(id: unique(SelectionTag.display(display.id)), kind: .display(display, depth: 0)))
        }
        for device in departing {
            rows.append(TopologyOutlineRow(id: unique("departing:\(device.id)"),
                                   kind: .device(device, depth: 0, isDeparting: true)))
        }
    }

    private mutating func append(_ device: DeviceNode, depth: Int, into rows: inout [TopologyOutlineRow]) {
        let id = unique(SelectionTag.device(device.id))
        rows.append(TopologyOutlineRow(id: id, kind: .device(device, depth: depth, isDeparting: false)))
        guard !collapsed.contains(id) else { return }
        for child in device.children { append(child, depth: depth + 1, into: &rows) }
    }
}

// MARK: - Row views

/// A port row: status, connector, name, transports and power.
struct OutlinePortRow: View {
    var port: PhysicalPort
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 10) {
            StatusRing(isActive: port.isConnected, size: 10)
            PortIcon(kind: port.kind, isActive: port.isConnected, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(port.label.title)
                    .lagoonFont(.headline, weight: .semibold)
                    .foregroundStyle(port.isConnected ? Lagoon.textPrimary : Lagoon.textSecondary)
                    .lineLimit(1)
                Text(subtitle)
                    .lagoonFont(.caption, monospacedDigits: true)
                    .foregroundStyle(Lagoon.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ForEach(port.activeTransports.prefix(2), id: \.kind) { transport in
                TransportChip(transport: transport)
                    .fixedSize()
            }
            if let reading = WindowText.portPower(port) {
                PowerBadge(milliwatts: reading.milliwatts, direction: reading.direction, isMeasured: reading.isMeasured)
                    .fixedSize()
            }
        }
        .padding(.vertical, 5)
        .opacity(port.isConnected ? 1 : WindowContrast.emptyOpacity(contrast, 0.6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WindowText.portAccessibility(port))
    }

    private var subtitle: String {
        var parts = [port.capabilityDescription ?? port.kind.displayName]
        if port.deviceCount > 0 {
            parts.append(WindowText.count(port.deviceCount, "device", "devices"))
        } else if !port.isConnected {
            parts.append("Empty")
        }
        return parts.joined(separator: " · ")
    }
}

/// Vertical guide lines for each level of nesting.
struct OutlineIndentGuides: View {
    /// Number of guide columns.
    var levels: Int
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<max(levels, 0), id: \.self) { _ in
                Rectangle()
                    .fill(WindowContrast.stroke(contrast))
                    .frame(width: 1)
                    .frame(width: 18)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.leading, 13)
        .accessibilityHidden(true)
    }
}

/// A device row with its link speed, power and (for containers) a roll-up.
struct OutlineDeviceRow: View {
    var device: DeviceNode
    var depth: Int
    var isDeparting: Bool
    var isExpanded: Bool
    var onToggle: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 8) {
            OutlineIndentGuides(levels: depth + 1)
            disclosure
            DeviceIcon(kind: device.kind, size: 24, dimmed: isDeparting)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .lagoonFont(.callout, weight: .semibold)
                    .foregroundStyle(isDeparting ? WindowContrast.tertiary(contrast) : Lagoon.textPrimary)
                    .lineLimit(1)
                Text(isDeparting ? "Disconnected" : subtitle)
                    .lagoonFont(.caption, monospacedDigits: true)
                    .foregroundStyle(isDeparting ? WindowContrast.tertiary(contrast) : Lagoon.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let link = device.link, !isDeparting {
                SpeedChip(link: link)
                    .fixedSize()
            }
            if let milliwatts = device.power?.allocatedMilliwatts, milliwatts > 0, !isDeparting {
                Text(Format.power(milliwatts: milliwatts))
                    .lagoonFont(.caption, monospacedDigits: true)
                    .foregroundStyle(Lagoon.textSecondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 5)
        .opacity(isDeparting ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(WindowText.deviceAccessibility(device, portTitle: nil, isDeparting: isDeparting))
    }

    @ViewBuilder
    private var disclosure: some View {
        if !device.children.isEmpty && !isDeparting {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .lagoonFont(size: 9, weight: .bold)
                    .foregroundStyle(Lagoon.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.snappy(duration: 0.2), value: isExpanded)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Expand")
            .accessibilityLabel(isExpanded ? "Collapse \(device.name)" : "Expand \(device.name)")
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }

    private var subtitle: String {
        var parts = [WindowText.deviceSubtitle(device)]
        if let vendor = device.vendorName, !vendor.isEmpty, !parts[0].contains(vendor) { parts.append(vendor) }
        return parts.joined(separator: " · ")
    }
}

/// A display that is not part of a device tree.
struct OutlineDisplayRow: View {
    var display: DisplayInfo
    var depth: Int

    var body: some View {
        HStack(spacing: 8) {
            OutlineIndentGuides(levels: depth + 1)
            Color.clear.frame(width: 14, height: 14)
            DeviceIcon(kind: .display, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name)
                    .lagoonFont(.callout, weight: .semibold)
                    .foregroundStyle(Lagoon.textPrimary)
                    .lineLimit(1)
                Text(display.modeDescription ?? "Display")
                    .lagoonFont(.caption, monospacedDigits: true)
                    .foregroundStyle(Lagoon.textSecondary)
            }
            Spacer(minLength: 8)
            if let link = display.link {
                SpeedChip(link: link)
                    .fixedSize()
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

/// Header row for devices and displays not tied to a port.
struct OutlineOtherRow: View {
    var count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.square.dashed")
                .lagoonFont(size: 13, weight: .semibold)
                .foregroundStyle(Lagoon.textSecondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Lagoon.surfaceRaised))
                .padding(.leading, 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Other devices")
                    .lagoonFont(.headline, weight: .semibold)
                    .foregroundStyle(Lagoon.textPrimary)
                Text("Not tied to a specific port · \(WindowText.count(count, "item", "items"))")
                    .lagoonFont(.caption, monospacedDigits: true)
                    .foregroundStyle(Lagoon.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .selectionDisabled()
        .accessibilityElement(children: .combine)
    }
}
