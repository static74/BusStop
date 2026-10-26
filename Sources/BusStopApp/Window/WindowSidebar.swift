import BusStopCore
import BusStopUI
import SwiftUI

/// What the topology window's sidebar can show.
enum TopologySidebarItem: Hashable {
    case overview
    /// The Mac Outline: each port drawn where it sits on the Mac.
    case silhouette
    case allPorts
    case port(PortKey)
    case devices
    case power
    case events
    case diagnostics

    /// The page a `topology:<page>` Automation value names: "overview",
    /// "silhouette", "allPorts", "devices", "power", "events", "diagnostics".
    /// Port pages have no name.
    init?(automationName: String) {
        let pages: [String: TopologySidebarItem] = [
            "overview": .overview, "silhouette": .silhouette, "allPorts": .allPorts, "devices": .devices,
            "power": .power, "events": .events, "diagnostics": .diagnostics,
        ]
        guard let page = pages[automationName] else { return nil }
        self = page
    }
}

/// Overview presentation: the drawn graph or an indented list.
enum TopologyOverviewMode: String, CaseIterable, Identifiable {
    case graph
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graph: return "Graph"
        case .list: return "List"
        }
    }

    var symbolName: String {
        switch self {
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .list: return "list.bullet.indent"
        }
    }
}

/// The window's sidebar: Overview, one row per port, then the detail pages.
/// It sits on the system's Liquid Glass sidebar; nothing is painted behind it.
struct WindowSidebar: View {
    var store: PortStore
    @Binding var selection: TopologySidebarItem?
    @AppStorage(TopologyWindowDefaults.cablesExpanded) private var cablesExpanded = true

    var body: some View {
        List(selection: $selection) {
            Section("Map") {
                Label("Overview", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(TopologySidebarItem.overview)
                Label("Mac Outline", systemImage: "desktopcomputer")
                    .tag(TopologySidebarItem.silhouette)
            }

            Section("Ports") {
                Label("All Ports", systemImage: "tablecells")
                    .tag(TopologySidebarItem.allPorts)
                ForEach(store.visiblePorts) { port in
                    SidebarPortRow(port: port)
                        .tag(TopologySidebarItem.port(port.key))
                }
            }

            cablesSection

            Section("Details") {
                Label("All Devices", systemImage: "list.bullet.rectangle")
                    .tag(TopologySidebarItem.devices)
                Label("Power", systemImage: "bolt")
                    .tag(TopologySidebarItem.power)
                eventsRow
                    .tag(TopologySidebarItem.events)
                diagnosticsRow
                    .tag(TopologySidebarItem.diagnostics)
            }
        }
        .listStyle(.sidebar)
    }

    /// Every link below the Mac's ports, one group per port. A row opens the
    /// link in the inspector and moves the map to it.
    private var cablesSection: some View {
        Section("Cables", isExpanded: $cablesExpanded) {
            ForEach(store.visiblePorts.filter { !$0.devices.isEmpty }) { port in
                let cables = SidebarCable.cables(below: port.devices, from: port.label.title)
                DisclosureGroup {
                    ForEach(cables) { cable in
                        let link = StoreSelection.link(.device(cable.deviceID))
                        SidebarCableRow(cable: cable, isSelected: store.selection == link) {
                            store.reveal(link)
                        }
                    }
                } label: {
                    HStack {
                        Label(port.label.title, systemImage: "cable.connector")
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        WindowCountBadge(count: cables.count, color: Lagoon.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var eventsRow: some View {
        HStack {
            Label("Events", systemImage: "clock.arrow.circlepath")
            Spacer(minLength: 4)
            // Events since launch; the saved log can hold thousands.
            let recent = store.events.prefix { $0.date >= store.launchDate }.count
            if recent > 0 {
                WindowCountBadge(count: recent, color: Lagoon.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var diagnosticsRow: some View {
        let diagnostics = store.snapshot.diagnostics
        let color = store.snapshot.worstSeverity.map(Lagoon.severityColor) ?? Lagoon.accent
        return HStack {
            Label("Diagnostics", systemImage: "stethoscope")
            Spacer(minLength: 4)
            if !diagnostics.isEmpty {
                WindowCountBadge(count: diagnostics.count, color: color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A port in the sidebar: status ring and its name.
struct SidebarPortRow: View {
    var port: PhysicalPort

    var body: some View {
        Label {
            Text(port.label.title)
                .lineLimit(1)
                .foregroundStyle(port.isConnected ? Lagoon.textPrimary : Lagoon.textSecondary)
        } icon: {
            StatusRing(isActive: port.isConnected, size: 11)
        }
        .help(port.isConnected ? "\(port.label.title): connected" : "\(port.label.title): empty")
        .accessibilityLabel(WindowText.portAccessibility(port))
    }
}

/// A link in the sidebar's Cables section: what it connects and its speed.
nonisolated struct SidebarCable: Identifiable {
    /// The device the link leads to.
    var deviceID: String
    var parentName: String
    var childName: String
    var link: LinkInfo?

    var id: String { deviceID }

    /// Every link below `devices` in tree order: from `parentName` to each
    /// device, then from each device to the ones below it.
    static func cables(below devices: [DeviceNode], from parentName: String) -> [SidebarCable] {
        devices.flatMap { device in
            [SidebarCable(deviceID: device.id, parentName: parentName, childName: device.name, link: device.link)]
                + cables(below: device.children, from: device.name)
        }
    }
}

/// One link in the Cables section: "parent → child" and the negotiated rate.
struct SidebarCableRow: View {
    var cable: SidebarCable
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        let title = "\(cable.parentName) → \(cable.childName)"
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(isSelected ? Lagoon.accent : Lagoon.textPrimary)
                Spacer(minLength: 4)
                if let rate = cable.link?.rateLabel {
                    Text(rate)
                        .lagoonFont(.caption2, monospacedDigits: true)
                        .foregroundStyle(Lagoon.textSecondary)
                        .fixedSize()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel([title, cable.link?.rateLabel].compactMap { $0 }.joined(separator: ", "))
    }
}
