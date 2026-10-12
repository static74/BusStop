import BusStopCore
import SwiftUI

/// What the topology window's sidebar can show.
enum TopologySidebarItem: Hashable {
    case overview
    case allPorts
    case port(PortKey)
    case devices
    case power
    case events
    case diagnostics
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

    var body: some View {
        List(selection: $selection) {
            Section("Map") {
                Label("Overview", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(TopologySidebarItem.overview)
            }

            Section("Ports") {
                Label("All Ports", systemImage: "tablecells")
                    .tag(TopologySidebarItem.allPorts)
                ForEach(store.visiblePorts) { port in
                    SidebarPortRow(port: port)
                        .tag(TopologySidebarItem.port(port.key))
                }
            }

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

    private var eventsRow: some View {
        HStack {
            Label("Events", systemImage: "clock.arrow.circlepath")
            Spacer(minLength: 4)
            if !store.events.isEmpty {
                WindowCountBadge(count: store.events.count, color: Lagoon.textSecondary)
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
