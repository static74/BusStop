import BusStopCore
import SwiftUI

// Temporary stubs replaced in the next commit.

struct PortsTableView: View {
    var store: PortStore
    var searchText: String
    var body: some View { Text("Ports") }
}

struct DevicesTableView: View {
    var store: PortStore
    var searchText: String
    var body: some View { Text("Devices") }
}

struct PowerDetailView: View {
    var store: PortStore
    var body: some View { Text("Power") }
}

struct EventsDetailView: View {
    var store: PortStore
    var searchText: String
    var body: some View { Text("Events") }
}

struct DiagnosticsDetailView: View {
    var store: PortStore
    var onShowPort: (PortKey) -> Void
    var onShowDevice: (String) -> Void
    var body: some View { Text("Diagnostics") }
}

struct TopologyOutlineView: View {
    var store: PortStore
    var ports: [PhysicalPort]
    var includeOther: Bool
    var searchText: String
    var body: some View { Text("List") }
}

struct InspectorView: View {
    var store: PortStore
    var body: some View { Text("Inspector") }
}
