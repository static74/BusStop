import BusStopCore
import SwiftUI

/// Root view of the topology window: a sidebar of pages, a detail area (the
/// graph, tables, power, events, diagnostics) and a trailing inspector for the
/// current selection.
///
/// Hosted by `WindowManager` in an `NSHostingController` with toolbar and
/// title bridging, so `.toolbar`, `.navigationTitle` and `.searchable` reach
/// the window. `WindowManager` also reports visibility to the store.
struct TopologyWindowView: View {
    var store: PortStore

    @State private var sidebarSelection: TopologySidebarItem? = .overview
    @State private var showInspector = false
    @State private var didSizeInspector = false
    @State private var searchText = ""
    @AppStorage("topologyOverviewMode") private var overviewMode: TopologyOverviewMode = .graph

    var body: some View {
        let settings = store.settings
        NavigationSplitView {
            WindowSidebar(store: store, selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 320)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { LagoonBackground(opacity: settings.backgroundOpacity) }
                .inspector(isPresented: $showInspector) {
                    InspectorView(store: store)
                        .inspectorColumnWidth(min: 270, ideal: 330, max: 480)
                }
                .toolbar { toolbarContent }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search ports and devices"))
        .navigationTitle(store.snapshot.machine.name)
        .navigationSubtitle(store.hasLoaded ? WindowText.summary(store.snapshot) : "Reading ports…")
        .preferredColorScheme(.dark)
        .tint(Lagoon.accent)
        .dynamicTypeSize(settings.textSize.dynamicTypeSize)
        .frame(minWidth: 860, minHeight: 540)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            guard !didSizeInspector, width > 0 else { return }
            didSizeInspector = true
            showInspector = width >= 1200
        }
        .onChange(of: sidebarSelection) { _, item in
            if case .port(let key)? = item { store.selection = .port(key) }
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if !store.hasLoaded {
            WindowLoadingView()
        } else {
            switch sidebarSelection ?? .overview {
            case .overview:
                overview(ports: store.visiblePorts, includeOther: true)
            case .port(let key):
                if let port = store.snapshot.port(key) {
                    overview(ports: [port], includeOther: false)
                } else {
                    EmptyStateView(
                        systemName: "cable.connector.slash",
                        title: "Port not available",
                        message: "This port is hidden or no longer reported by macOS."
                    )
                }
            case .allPorts:
                PortsTableView(store: store, searchText: searchText)
            case .devices:
                DevicesTableView(store: store, searchText: searchText)
            case .power:
                PowerDetailView(store: store)
            case .events:
                EventsDetailView(store: store, searchText: searchText)
            case .diagnostics:
                DiagnosticsDetailView(store: store, onShowPort: showPort, onShowDevice: showDevice)
            }
        }
    }

    @ViewBuilder
    private func overview(ports: [PhysicalPort], includeOther: Bool) -> some View {
        switch overviewMode {
        case .graph:
            TopologyGraphView(store: store, ports: ports, includeOther: includeOther, searchText: searchText)
        case .list:
            TopologyOutlineView(store: store, ports: ports, includeOther: includeOther, searchText: searchText)
        }
    }

    private var showsModePicker: Bool {
        switch sidebarSelection ?? .overview {
        case .overview, .port: return true
        default: return false
        }
    }

    private func showPort(_ key: PortKey) {
        store.selection = .port(key)
        if store.visiblePorts.contains(where: { $0.key == key }) {
            sidebarSelection = .port(key)
        } else {
            sidebarSelection = .overview
        }
    }

    private func showDevice(_ id: String) {
        store.selection = .device(id)
        sidebarSelection = .overview
        showInspector = true
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if showsModePicker {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $overviewMode) {
                    ForEach(TopologyOverviewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbolName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.titleAndIcon)
                .help("Show the topology as a graph or as a list")
            }
        }

        if store.isDemo {
            ToolbarItem(placement: .primaryAction) {
                DemoBadge()
            }
            .sharedBackgroundVisibility(.hidden)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                store.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Read the ports again")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                ForEach(ExportKind.allCases) { kind in
                    Button(kind.title) {
                        ExportController.export(kind, store: store)
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export a snapshot, a report or a raw capture")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation(.snappy) { showInspector.toggle() }
            } label: {
                Label(showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(showInspector ? "Hide the inspector" : "Show the inspector")
        }
    }
}
