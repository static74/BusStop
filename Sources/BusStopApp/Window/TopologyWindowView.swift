import BusStopCore
import SwiftUI

/// Root view of the topology window: a sidebar of pages, a detail area (the
/// graph, tables, power, events, diagnostics) and a trailing inspector for the
/// current selection.
///
/// Hosted by `WindowManager` in an `NSHostingController` with toolbar and
/// title bridging, so `.toolbar`, `.navigationTitle` and `.searchable` reach
/// the window. `WindowManager` also reports visibility to the store.
///
/// `PortStore.reveal(_:)` (Show in Topology, the diagnostics banner, the
/// Diagnostics page) bumps `revealGeneration`; the window then switches to a
/// page that shows the selection, opens the inspector and scrolls the graph
/// or list to it.
struct TopologyWindowView: View {
    var store: PortStore

    @State private var sidebarSelection: TopologySidebarItem? = .overview
    @State private var showInspector = false
    @State private var didSizeInspector = false
    @State private var searchText = ""
    /// The zoom the user picked; nil fits the graph to the window. Cleared
    /// when the window closes, so it fits again when reopened.
    @State private var userZoom: Double?
    /// On screen, not minimised and not covered: the graph pulses only then.
    @State private var isWindowVisible = true
    /// The last `store.revealGeneration` this window acted on.
    @State private var handledReveal = 0
    /// A node waiting to be scrolled into view by the graph or the list.
    @State private var scrollRequest: TopologyScrollRequest?
    @AppStorage(TopologyWindowDefaults.overviewMode) private var overviewMode: TopologyOverviewMode = .graph

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
        .lagoonFont(.body)
        .lagoonTextScale(settings.textSize)
        .frame(minWidth: 860, minHeight: 540)
        .background {
            HostingWindowObserver(
                onVisibilityChange: { isWindowVisible = $0 },
                onClose: { userZoom = nil }
            )
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            guard !didSizeInspector, width > 0 else { return }
            didSizeInspector = true
            if !showInspector { showInspector = width >= 1200 }
        }
        .onChange(of: sidebarSelection) { _, item in
            if case .port(let key)? = item { store.selection = .port(key) }
        }
        .onChange(of: store.revealGeneration, initial: true) { _, generation in
            handleReveal(generation)
        }
        .onAppear { SystemLoadRecorder.shared.start(store: store) }
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
                    WindowEmptyState(
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
                EventsDetailView(store: store, searchText: searchText, onSelect: showInInspector)
            case .diagnostics:
                DiagnosticsDetailView(
                    store: store,
                    onShowPort: { store.reveal(.port($0)) },
                    onShowDevice: { store.reveal(.device($0)) }
                )
            }
        }
    }

    @ViewBuilder
    private func overview(ports: [PhysicalPort], includeOther: Bool) -> some View {
        switch overviewMode {
        case .graph:
            TopologyGraphView(
                store: store,
                ports: ports,
                includeOther: includeOther,
                searchText: searchText,
                userZoom: $userZoom,
                isWindowVisible: isWindowVisible,
                scrollRequest: $scrollRequest
            )
        case .list:
            TopologyOutlineView(
                store: store,
                ports: ports,
                includeOther: includeOther,
                searchText: searchText,
                scrollRequest: $scrollRequest
            )
        }
    }

    private var showsModePicker: Bool {
        switch sidebarSelection ?? .overview {
        case .overview, .port: return true
        default: return false
        }
    }

    // MARK: Navigation

    /// Selects without leaving the page, and shows the inspector (Events).
    private func showInInspector(_ selection: StoreSelection) {
        store.selection = selection
        withAnimation(.snappy) { showInspector = true }
    }

    /// Brings `store.selection` into view after `PortStore.reveal(_:)`.
    private func handleReveal(_ generation: Int) {
        guard generation != handledReveal else { return }
        handledReveal = generation
        guard let selection = store.selection else { return }
        let page = Self.page(revealing: selection, from: sidebarSelection ?? .overview, store: store)
        withAnimation(.snappy) {
            sidebarSelection = page
            showInspector = true
        }
        scrollRequest = TopologyScrollRequest(generation: generation, tag: SelectionTag.string(for: selection))
    }

    /// The page that shows `selection`. A graph page that already contains it
    /// stays; otherwise a port goes to its own page and everything else to the
    /// Overview. A device never opens a port page, because opening one
    /// selects the port.
    static func page(revealing selection: StoreSelection, from current: TopologySidebarItem,
                     store: PortStore) -> TopologySidebarItem {
        switch current {
        case .overview:
            return .overview
        case .port(let key):
            if selection == .host || owningPort(of: selection, in: store.snapshot) == key { return current }
            return .overview
        default:
            if case .port(let key) = selection, store.visiblePorts.contains(where: { $0.key == key }) {
                return .port(key)
            }
            return .overview
        }
    }

    /// The port a selection belongs to, if any.
    private static func owningPort(of selection: StoreSelection, in snapshot: HostSnapshot) -> PortKey? {
        switch selection {
        case .host: return nil
        case .port(let key): return key
        case .device(let id): return snapshot.port(containing: id)?.key
        case .display(let id): return snapshot.displays.first { $0.id == id }?.portKey
        }
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
