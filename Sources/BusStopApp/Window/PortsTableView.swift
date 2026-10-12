import BusStopCore
import SwiftUI

/// One row of the Ports table. Plain values only, so key paths are Sendable
/// and every column sorts with a `KeyPathComparator`.
nonisolated struct PortTableRow: Identifiable, Sendable {
    /// `SelectionTag.port(key)`.
    var id: String
    var key: PortKey
    var kind: PortKind
    /// Position in the window's port order (default sort).
    var order: Int
    var title: String
    var connector: String
    var isConnected: Bool
    var status: String
    /// Sorts empty ports last.
    var statusRank: Int
    var link: LinkInfo?
    var linkLabel: String
    var linkBits: Int64
    var power: WindowPowerReading?
    /// Signed: positive out of the Mac, negative into it.
    var powerSort: Int
    var deviceCount: Int
    var capability: String
}

/// Every port as a sortable table. Selecting a row selects the port.
struct PortsTableView: View {
    var store: PortStore
    var searchText: String

    @State private var sortOrder = [KeyPathComparator(\PortTableRow.order)]

    var body: some View {
        let rows = makeRows().sorted(using: sortOrder)
        VStack(alignment: .leading, spacing: 14) {
            WindowDetailHeader(
                title: "Ports",
                subtitle: "\(WindowText.count(store.snapshot.ports.count, "port", "ports")) · \(store.snapshot.connectedPorts.count) in use"
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)

            if rows.isEmpty {
                PortListEmptyView(state: PortListEmptyState.resolve(searchText: searchText, store: store), store: store)
            } else {
                table(rows)
            }
        }
    }

    private func table(_ rows: [PortTableRow]) -> some View {
        Table(rows, selection: selection, sortOrder: $sortOrder) {
            TableColumn("Port", value: \PortTableRow.title) { row in
                HStack(spacing: 8) {
                    StatusRing(isActive: row.isConnected, size: 9)
                    PortIcon(kind: row.kind, isActive: row.isConnected, size: 20)
                    Text(row.title)
                        .foregroundStyle(row.isConnected ? Lagoon.textPrimary : Lagoon.textSecondary)
                        .lineLimit(1)
                }
            }
            .width(min: 170, ideal: 220)

            TableColumn("Connector", value: \PortTableRow.connector) { row in
                Text(row.connector).foregroundStyle(Lagoon.textSecondary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Status", value: \PortTableRow.statusRank) { row in
                Text(row.status)
                    .foregroundStyle(row.isConnected ? Lagoon.accent : Lagoon.textTertiary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Link", value: \PortTableRow.linkBits) { row in
                if let link = row.link {
                    SpeedChip(link: link, compact: false)
                } else {
                    Text("—").foregroundStyle(Lagoon.textTertiary)
                }
            }
            .width(min: 120, ideal: 210)

            TableColumn("Power", value: \PortTableRow.powerSort) { row in
                if let power = row.power {
                    PowerBadge(milliwatts: power.milliwatts, direction: power.direction, isMeasured: power.isMeasured)
                } else {
                    Text("—").foregroundStyle(Lagoon.textTertiary)
                }
            }
            .width(min: 70, ideal: 90)

            TableColumn("Devices", value: \PortTableRow.deviceCount) { row in
                Text(row.deviceCount > 0 ? "\(row.deviceCount)" : "—")
                    .monospacedDigit()
                    .foregroundStyle(row.deviceCount > 0 ? Lagoon.textPrimary : Lagoon.textTertiary)
            }
            .width(min: 56, ideal: 64)

            TableColumn("Capability", value: \PortTableRow.capability) { row in
                Text(row.capability)
                    .foregroundStyle(Lagoon.textSecondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        .lagoonFont(.body)
    }

    private var selection: Binding<String?> {
        Binding(
            get: {
                if case .port(let key)? = store.selection { return SelectionTag.port(key) }
                return nil
            },
            set: { tag in
                if let selection = SelectionTag.selection(for: tag) { store.selection = selection }
            }
        )
    }

    private func makeRows() -> [PortTableRow] {
        let query = TopologySearch.normalized(searchText)
        var rows: [PortTableRow] = []
        for (index, port) in store.visiblePorts.enumerated() {
            let deviceMatch = port.allDevices.contains { TopologySearch.device($0.device, matches: query) }
            guard TopologySearch.port(port, matches: query) || deviceMatch else { continue }
            let reading = WindowText.portPower(port)
            var powerSort = 0
            if let reading {
                powerSort = reading.direction == .input ? -reading.milliwatts : reading.milliwatts
            }
            rows.append(PortTableRow(
                id: SelectionTag.port(port.key),
                key: port.key,
                kind: port.kind,
                order: index,
                title: port.label.title,
                connector: port.kind.displayName,
                isConnected: port.isConnected,
                status: port.isConnected ? "Connected" : "Empty",
                statusRank: port.isConnected ? 0 : 1,
                link: port.link,
                linkLabel: port.link?.label ?? "",
                linkBits: port.link?.bitsPerSecond ?? 0,
                power: reading,
                powerSort: powerSort,
                deviceCount: port.deviceCount,
                capability: port.capabilityDescription ?? "—"
            ))
        }
        return rows
    }
}
