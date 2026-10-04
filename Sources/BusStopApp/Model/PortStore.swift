import BusStopCore
import BusStopKit
import Foundation
import Observation

/// What is selected in the topology window.
enum StoreSelection: Hashable {
    case host
    case port(PortKey)
    case device(String)
    case display(String)
}

/// A device that just disappeared, kept briefly so the UI can fade it out
/// instead of making the list jump (and so a flaky cable does not flicker).
struct DepartingDevice: Identifiable, Hashable {
    /// The device as it was, with the children that left with it.
    var device: DeviceNode
    var portKey: PortKey?
    /// The device it hung off, or nil when it was plugged straight into the
    /// port (or listed at the top of the Other group).
    var parentID: String? = nil
    /// Its position among its siblings before it left, so the ghost keeps
    /// its slot.
    var index: Int = 0
    var removedAt: Date
    var id: String { device.id }
}

/// The app's single source of truth: the latest snapshot, event log and power
/// history. Owns the live monitor (or the demo ticker).
@Observable
final class PortStore {
    private(set) var snapshot: HostSnapshot = .placeholder()
    private(set) var raw: RawSnapshot?
    /// Newest first, capped at `maxEvents`.
    private(set) var events: [ConnectionEvent] = []
    private(set) var history = PowerHistory()
    private(set) var lastUpdated: Date?
    private(set) var hasLoaded = false
    /// Every device that just disappeared, nested ones included. Most views
    /// want `devicesWithGhosts(on:)` instead.
    private(set) var allDeparting: [DepartingDevice] = []
    var selection: StoreSelection? = .host
    /// Bumped by `reveal(_:)`. The topology window watches it to navigate to
    /// the selection (switch sidebar section, scroll the graph, show the
    /// inspector) even when the selection itself did not change.
    private(set) var revealGeneration = 0

    /// Called with the events of each live refresh (used for notifications).
    /// Never called for demo data.
    @ObservationIgnored var onEvents: (([ConnectionEvent]) -> Void)?

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored private var monitor: LiveMonitor?
    @ObservationIgnored private var demoTimer: Timer?
    @ObservationIgnored private var demoTick = 0
    /// The scenario the demo capture currently comes from; nil when no demo
    /// capture has been taken since the last start.
    @ObservationIgnored private var runningScenario: DemoScenario?
    /// The live event log, kept aside while demo mode is on.
    @ObservationIgnored private var liveEventsDuringDemo: [ConnectionEvent] = []
    @ObservationIgnored private var overcurrentBaseline: [String: Int] = [:]
    @ObservationIgnored private var visibleClients = 0
    @ObservationIgnored private var isRunning = false

    static let maxEvents = 500
    static let departingLifetime: TimeInterval = 1.5

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    var isDemo: Bool { settings.demoMode }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        if settings.demoMode {
            startDemo()
        } else {
            startLive()
        }
    }

    func stop() {
        isRunning = false
        monitor?.stop()
        monitor = nil
        demoTimer?.invalidate()
        demoTimer = nil
        runningScenario = nil
    }

    /// Re-reads settings that affect data collection (demo mode, demo
    /// scenario, polling, SMC) and rebuilds the snapshot so renamed ports show
    /// at once.
    ///
    /// Switching between live data and demo mode, or between demo scenarios,
    /// changes the source of the data rather than the hardware: the new source
    /// starts from scratch with no connect or disconnect events, no
    /// notifications, no ghosts and a fresh power history. The event log never
    /// mixes sources: demo events are dropped when the source changes, and the
    /// live log is set aside while demo mode is on and comes back when it ends.
    func applySettings() {
        let wantsDemo = settings.demoMode
        let isDemoRunning = demoTimer != nil
        if isRunning && wantsDemo != isDemoRunning {
            stop()
            if wantsDemo {
                liveEventsDuringDemo = events
                resetForSourceChange()
            } else {
                resetForSourceChange()
                events = liveEventsDuringDemo
                liveEventsDuringDemo = []
            }
            start()
            return
        }
        if wantsDemo {
            // A different scenario resets the store inside ingestDemo().
            ingestDemo()
        } else {
            monitor?.update(configuration: monitorConfiguration)
            if let raw { ingest(raw) }
        }
    }

    func refresh() {
        if settings.demoMode {
            demoTick += 1
            ingestDemo()
        } else {
            monitor?.refreshNow()
        }
    }

    /// Popover and windows call this when they appear (true) and disappear
    /// (false) so power polling runs faster only while someone is looking.
    func setUIVisible(_ visible: Bool) {
        visibleClients = max(0, visibleClients + (visible ? 1 : -1))
        monitor?.setUIVisible(visibleClients > 0)
    }

    // MARK: Ports

    func portNameKey(_ key: PortKey) -> String { "\(snapshot.machine.model)#\(key.description)" }

    /// Sets or clears (`nil` / empty) the user's name for a port.
    func renamePort(_ key: PortKey, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var names = settings.portNames
        names[portNameKey(key)] = trimmed.isEmpty ? nil : trimmed
        settings.portNames = names
        if let raw { ingest(raw) }
    }

    func resetPortNames() {
        let prefix = "\(snapshot.machine.model)#"
        settings.portNames = settings.portNames.filter { !$0.key.hasPrefix(prefix) }
        if let raw { ingest(raw) }
    }

    /// Ports in the order chosen in settings, optionally without empty ones.
    ///
    /// A port whose device just left still counts as in use while its ghost
    /// fades, so "Hide empty ports" and "Connected first" move or hide the
    /// card only after the ghost is gone, and not at all if the device comes
    /// straight back.
    var visiblePorts: [PhysicalPort] {
        let ghostKeys = Set(allDeparting.compactMap(\.portKey))
        let inUse: (PhysicalPort) -> Bool = { $0.isConnected || ghostKeys.contains($0.key) }
        var ports = snapshot.ports
        if settings.hideEmptyPorts { ports = ports.filter(inUse) }
        if settings.portOrder == .connectedFirst {
            ports = ports.filter(inUse) + ports.filter { !inUse($0) }
        }
        return ports
    }

    /// Selects `selection` and asks the topology window to bring it into view.
    func reveal(_ selection: StoreSelection) {
        self.selection = selection
        revealGeneration += 1
    }

    /// Departing devices that were plugged straight into a port or listed
    /// at the top of the Other group. Nested ghosts are in `allDeparting`.
    var departing: [DepartingDevice] {
        allDeparting.filter { $0.parentID == nil }
    }

    /// Top-level departing devices on `key` (nil: the Other group).
    func departing(on key: PortKey?) -> [DepartingDevice] {
        departing.filter { $0.portKey == key }
    }

    /// IDs of every device shown as a ghost, nested ones included.
    var departingIDs: Set<String> {
        Set(allDeparting.map(\.id))
    }

    /// Whether `id` is a device that just left and is shown as a ghost.
    func isDeparting(_ id: String) -> Bool {
        allDeparting.contains { $0.id == id }
    }

    /// The device tree on `key` (nil: the Other group) with each departing
    /// device put back where it was, so the rows around it keep their place
    /// while it fades (docs/SPEC.md §4.5). A ghost whose parent has also gone
    /// is shown at the top level. Use `departingIDs` to style ghosts; their
    /// descendants left with them.
    func devicesWithGhosts(on key: PortKey?) -> [DeviceNode] {
        let live: [DeviceNode]
        if let key {
            live = snapshot.port(key)?.devices ?? []
        } else {
            live = snapshot.otherDevices
        }
        let ghosts = allDeparting.filter { $0.portKey == key }
        guard !ghosts.isEmpty else { return live }

        let liveIDs = Set(live.flatMap { $0.flattened().map(\.device.id) })
        var ghostsByParent: [String: [DepartingDevice]] = [:]
        var topLevel: [DepartingDevice] = []
        for ghost in ghosts {
            if let parentID = ghost.parentID, liveIDs.contains(parentID) {
                ghostsByParent[parentID, default: []].append(ghost)
            } else {
                topLevel.append(ghost)
            }
        }

        func merged(_ nodes: [DeviceNode], ghosts: [DepartingDevice]) -> [DeviceNode] {
            var result = nodes.map { node -> DeviceNode in
                let ownGhosts = ghostsByParent[node.id] ?? []
                guard !ownGhosts.isEmpty || !node.children.isEmpty else { return node }
                var copy = node
                copy.children = merged(node.children, ghosts: ownGhosts)
                return copy
            }
            for ghost in ghosts.sorted(by: { $0.index < $1.index }) {
                result.insert(ghost.device, at: min(max(ghost.index, 0), result.count))
            }
            return result
        }
        return merged(live, ghosts: topLevel)
    }

    // MARK: Events

    func clearEvents() { events.removeAll() }

    // MARK: Export

    func exportJSON() throws -> Data { try Exporter.json(snapshot, redact: settings.redactExports) }
    func exportMarkdown() -> String { Exporter.markdown(snapshot, redact: settings.redactExports) }
    func exportRawJSON() throws -> Data? {
        guard let raw else { return nil }
        return try Exporter.rawJSON(raw, redact: settings.redactExports)
    }

    // MARK: Private

    private var monitorConfiguration: LiveMonitor.Configuration {
        LiveMonitor.Configuration(
            visibleInterval: max(1, settings.powerPollInterval),
            backgroundInterval: 10,
            debounce: 0.25,
            includeSMC: settings.readSMC
        )
    }

    private func startLive() {
        let monitor = LiveMonitor(configuration: monitorConfiguration)
        self.monitor = monitor
        monitor.setUIVisible(visibleClients > 0)
        monitor.start { [weak self] raw in
            self?.ingest(raw)
        }
    }

    private func startDemo() {
        demoTick = 0
        ingestDemo()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.demoTick += 1
                self.ingestDemo()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        demoTimer = timer
    }

    /// Ingests the selected demo scenario. Every demo capture goes through
    /// here, so a scenario change is caught by whichever path sees it first
    /// (the settings change, the timer or a refresh) and becomes a source
    /// change instead of a diff between two different Macs.
    private func ingestDemo() {
        let scenario = settings.demoScenario
        if scenario != runningScenario {
            if runningScenario != nil { resetForSourceChange() }
            runningScenario = scenario
            demoTick = 0
        }
        ingest(scenario.raw(at: Date(), tick: demoTick))
    }

    /// Forgets everything that came from the previous source. The next
    /// capture is treated as the first one, so it raises no events.
    private func resetForSourceChange() {
        snapshot = .placeholder()
        raw = nil
        history.removeAll()
        allDeparting.removeAll()
        overcurrentBaseline.removeAll()
        events.removeAll()
        hasLoaded = false
        selection = .host
    }

    private func userPortNames(for model: String) -> [String: String] {
        let prefix = "\(model)#"
        var result: [String: String] = [:]
        for (key, value) in settings.portNames where key.hasPrefix(prefix) {
            result[String(key.dropFirst(prefix.count))] = value
        }
        return result
    }

    private func ingest(_ raw: RawSnapshot) {
        // A capture of a different Mac model cannot be a hardware change on
        // this one, so treat it as a new source instead of diffing two Macs.
        if hasLoaded && raw.machine.model != snapshot.machine.model {
            resetForSourceChange()
        }
        let options = BuildOptions(
            userPortNames: userPortNames(for: raw.machine.model),
            includeRawProperties: true,
            isDemo: settings.demoMode
        )
        var built = TopologyBuilder.build(raw, options: options)

        if overcurrentBaseline.isEmpty {
            for port in built.ports {
                if let count = port.statistics?.overcurrentCount { overcurrentBaseline[port.id] = count }
            }
        }
        built.diagnostics = DiagnosticsEngine.evaluate(built, raw: raw, baseline: overcurrentBaseline)

        let previous = hasLoaded ? snapshot : nil
        let newEvents = SnapshotDiffer.events(from: previous, to: built, at: built.capturedAt)

        trackDeparting(previous: previous, current: built)

        self.raw = raw
        snapshot = built
        history.append(built)
        lastUpdated = built.capturedAt
        hasLoaded = true

        if !newEvents.isEmpty {
            events.insert(contentsOf: newEvents.reversed(), at: 0)
            if events.count > Self.maxEvents { events.removeLast(events.count - Self.maxEvents) }
            // Demo data never raises system notifications.
            if !built.isDemo { onEvents?(newEvents) }
        }

        if case .port(let key)? = selection, built.port(key) == nil { selection = .host }
        if case .device(let id)? = selection, built.device(id: id) == nil { selection = .host }
    }

    /// Records the devices that left between `previous` and `current`, at
    /// any depth, with their parent and position. A device that left with
    /// its parent is part of the parent's ghost, so pulling a hub gives one
    /// ghost (the hub, drawn with its children), not one per device.
    private func trackDeparting(previous: HostSnapshot?, current: HostSnapshot) {
        let now = Date()
        allDeparting.removeAll { now.timeIntervalSince($0.removedAt) > Self.departingLifetime }
        guard let previous else { return }
        let currentIDs = Set(current.allDevices.map(\.device.id))
        // Devices that came back are no longer departing.
        allDeparting.removeAll { currentIDs.contains($0.id) }

        // The departed device without any descendant that is still connected
        // somewhere else, so nothing is drawn twice.
        func ghost(of node: DeviceNode) -> DeviceNode {
            var copy = node
            copy.children = node.children.filter { !currentIDs.contains($0.id) }.map { ghost(of: $0) }
            return copy
        }

        var known = Set(allDeparting.map(\.id))
        func walk(_ nodes: [DeviceNode], parentID: String?, portKey: PortKey?) {
            for (index, node) in nodes.enumerated() {
                if currentIDs.contains(node.id) {
                    walk(node.children, parentID: node.id, portKey: portKey)
                } else if known.insert(node.id).inserted {
                    allDeparting.append(DepartingDevice(device: ghost(of: node), portKey: portKey,
                                                        parentID: parentID, index: index, removedAt: now))
                }
            }
        }
        for port in previous.ports {
            walk(port.devices, parentID: nil, portKey: port.key)
        }
        walk(previous.otherDevices, parentID: nil, portKey: nil)

        if !allDeparting.isEmpty {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.departingLifetime + 0.1))
                guard let self else { return }
                let cutoff = Date()
                self.allDeparting.removeAll { cutoff.timeIntervalSince($0.removedAt) > Self.departingLifetime }
            }
        }
    }
}
