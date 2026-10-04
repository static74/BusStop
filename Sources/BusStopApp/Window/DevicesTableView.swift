import BusStopCore
import SwiftUI

/// One row of the All Devices table. Plain values only, so every column sorts
/// with a `KeyPathComparator`.
nonisolated struct DeviceTableRow: Identifiable, Sendable {
    /// `SelectionTag.device(id)` or `SelectionTag.display(id)`.
    var id: String
    /// Depth-first order across ports (default sort).
    var order: Int
    var name: String
    var depth: Int
    var kind: DeviceKind
    var kindName: String
    var portTitle: String
    var link: LinkInfo?
    var speedLabel: String
    var speedBits: Int64
    var powerMilliwatts: Int
    var vendor: String
    var vidPid: String
    var serial: String
    var locationID: String
}

/// Every device, flat, as a sortable table. Selecting a row selects the device.
struct DevicesTableView: View {
    var store: PortStore
    var searchText: String

    @State private var sortOrder = [KeyPathComparator(\DeviceTableRow.order)]

    var body: some View {
        let rows = makeRows().sorted(using: sortOrder)
        VStack(alignment: .leading, spacing: 14) {
            WindowDetailHeader(
                title: "All Devices",
                subtitle: WindowText.count(store.snapshot.deviceCount, "device", "devices") + " on every port and hub"
            )
            .padding(.horizontal, 24)
            .padding(.top, 20)

            if rows.isEmpty {
                EmptyStateView(
                    systemName: searchText.isEmpty ? "cable.connector" : "magnifyingglass",
                    title: searchText.isEmpty ? "Nothing connected" : "No matches",
                    message: searchText.isEmpty
                        ? "Plug in a drive, hub, display or phone and it appears here."
                        : "No device matches your search."
                )
            } else {
                table(rows)
            }
        }
    }

    private func table(_ rows: [DeviceTableRow]) -> some View {
        Table(rows, selection: selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \DeviceTableRow.name) { row in
                HStack(spacing: 8) {
                    DeviceIcon(kind: row.kind, size: 20)
                    Text(row.name)
                        .foregroundStyle(Lagoon.textPrimary)
                        .lineLimit(1)
                }
                .padding(.leading, CGFloat(min(row.depth, 6)) * 12)
            }
            .width(min: 160, ideal: 220)

            TableColumn("Kind", value: \DeviceTableRow.kindName) { row in
                Text(row.kindName).foregroundStyle(Lagoon.textSecondary)
            }
            .width(min: 70, ideal: 100)

            TableColumn("Port", value: \DeviceTableRow.portTitle) { row in
                Text(row.portTitle)
                    .foregroundStyle(Lagoon.textSecondary)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Speed", value: \DeviceTableRow.speedBits) { row in
                if let link = row.link {
                    SpeedChip(link: link, compact: false)
                } else {
                    Text("—").foregroundStyle(Lagoon.textTertiary)
                }
            }
            .width(min: 110, ideal: 200)

            TableColumn("Power", value: \DeviceTableRow.powerMilliwatts) { row in
                Text(row.powerMilliwatts > 0 ? Format.power(milliwatts: row.powerMilliwatts) : "—")
                    .monospacedDigit()
                    .foregroundStyle(row.powerMilliwatts > 0 ? Lagoon.textPrimary : Lagoon.textTertiary)
            }
            .width(min: 56, ideal: 70)

            TableColumn("Vendor", value: \DeviceTableRow.vendor) { row in
                Text(row.vendor)
                    .foregroundStyle(Lagoon.textSecondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 120)

            TableColumn("VID:PID", value: \DeviceTableRow.vidPid) { row in
                Text(row.vidPid)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Lagoon.textSecondary)
            }
            .width(min: 100, ideal: 120)

            TableColumn("Serial", value: \DeviceTableRow.serial) { row in
                Text(row.serial)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Lagoon.textSecondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            .width(min: 80, ideal: 130)

            TableColumn("Location ID", value: \DeviceTableRow.locationID) { row in
                Text(row.locationID)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Lagoon.textSecondary)
            }
            .width(min: 90, ideal: 110)
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
    }

    private var selection: Binding<String?> {
        Binding(
            get: {
                switch store.selection {
                case .device(let id)?: return SelectionTag.device(id)
                case .display(let id)?: return SelectionTag.display(id)
                default: return nil
                }
            },
            set: { tag in
                if let selection = SelectionTag.selection(for: tag) { store.selection = selection }
            }
        )
    }

    private func makeRows() -> [DeviceTableRow] {
        let snapshot = store.snapshot
        let query = TopologySearch.normalized(searchText)
        var rows: [DeviceTableRow] = []
        var used: Set<String> = []

        for entry in snapshot.allDevices {
            let device = entry.device
            let portTitle = entry.port?.label.title ?? "Not tied to a port"
            let portMatches = entry.port.map { TopologySearch.port($0, matches: query) } ?? false
            guard portMatches || TopologySearch.device(device, matches: query) else { continue }
            let id = SelectionTag.device(device.id)
            guard used.insert(id).inserted else { continue }
            rows.append(DeviceTableRow(
                id: id,
                order: rows.count,
                name: device.name,
                depth: entry.depth,
                kind: device.kind,
                kindName: device.kind.displayName,
                portTitle: portTitle,
                link: device.link,
                speedLabel: device.link?.label ?? "",
                speedBits: device.link?.bitsPerSecond ?? 0,
                powerMilliwatts: device.power?.allocatedMilliwatts ?? 0,
                vendor: device.vendorName ?? "—",
                vidPid: device.vendorProductIDString ?? "—",
                serial: device.serialNumber ?? "—",
                locationID: device.locationID.map(Format.hex8) ?? "—"
            ))
        }

        let portDisplays = TopologyExtras.portDisplays(in: snapshot, ports: snapshot.ports)
        let extraDisplays = snapshot.ports.flatMap { portDisplays[$0.key] ?? [] }
            + TopologyExtras.otherDisplays(in: snapshot)
        for display in extraDisplays where TopologySearch.display(display, matches: query) {
            let id = SelectionTag.display(display.id)
            guard used.insert(id).inserted else { continue }
            rows.append(DeviceTableRow(
                id: id,
                order: rows.count,
                name: display.name,
                depth: 0,
                kind: .display,
                kindName: DeviceKind.display.displayName,
                portTitle: display.portKey.flatMap { snapshot.port($0)?.label.title } ?? "Not tied to a port",
                link: display.link,
                speedLabel: display.link?.label ?? "",
                speedBits: display.link?.bitsPerSecond ?? 0,
                powerMilliwatts: 0,
                vendor: "—",
                vidPid: vidPid(display),
                serial: display.serialNumber.map { "\($0)" } ?? "—",
                locationID: "—"
            ))
        }
        return rows
    }

    private func vidPid(_ display: DisplayInfo) -> String {
        guard let vendor = display.vendorID, let product = display.productID else { return "—" }
        return "\(Format.hex4(vendor)):\(Format.hex4(product))"
    }
}
