import AppKit
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
    /// The link that leads to a port, device or display: in the graph, the
    /// line drawn to it (for a port or a device plugged straight into one,
    /// the cable in the Mac's port).
    indirect case link(StoreSelection)
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
/// history. Owns the live monitor (or the demo ticker) and the saved history
/// (SPEC §5.6).
@Observable
final class PortStore {
    private(set) var snapshot: HostSnapshot = .placeholder()
    private(set) var raw: RawSnapshot?
    /// This Mac model's event log from the history archive, newest first.
    /// Filled by the first capture after a start.
    private(set) var events: [ConnectionEvent] = []
    /// What Settings shows about the saved history. Refreshed on load, save and clear.
    private(set) var historySummary = HistoryArchive.Summary()
    /// The saved file was written by a newer Bus Stop, so it is never overwritten.
    private(set) var historyIsReadOnly = false
    /// The sidebar badge counts events since this moment.
    let launchDate = Date()
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
    @ObservationIgnored let historyFile: HistoryFile?
    /// Changes on every capture, so no view observes it.
    @ObservationIgnored private(set) var archive = HistoryArchive()
    /// True while `archive` holds demo data, which is never saved.
    @ObservationIgnored private var archiveHoldsDemo = false
    /// The live archive, kept aside while demo mode is on.
    @ObservationIgnored private var heldLiveArchive: HistoryArchive?
    /// Set once the file has been read (or found missing), so a save never
    /// replaces a file that was not loaded.
    @ObservationIgnored private var historyLoaded = false
    /// The next capture follows launch, wake or a change of source, so the
    /// archive counts nothing across it.
    @ObservationIgnored private var nextCaptureAfterGap = true
    /// Settings changes re-ingest the same capture; it is recorded once.
    @ObservationIgnored private var lastRecordedAt: Date?
    @ObservationIgnored private var eventsDirty = false
    @ObservationIgnored private var powerDirty = false
    @ObservationIgnored private var lastSave = Date()
    @ObservationIgnored private var saveTimer: Timer?
    @ObservationIgnored private var overcurrentBaseline: [String: Int] = [:]
    @ObservationIgnored private var visibleClients = 0
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var screensAsleep = false
    @ObservationIgnored private var sessionInactive = false
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []

    static let departingLifetime: TimeInterval = 1.5
    /// Power changes on every capture; saving it this rarely keeps disk writes
    /// small. New events are saved within a minute.
    static let powerSaveInterval: TimeInterval = 15 * 60

    /// Only the app passes a `historyFile`; without one nothing is read or saved.
    init(settings: AppSettings = .shared, historyFile: HistoryFile? = nil) {
        self.settings = settings
        self.historyFile = historyFile
        observeScreenSleep()
    }

    /// Nobody can see the menu bar's power text, so power polling stops.
    var isPollingPaused: Bool { screensAsleep || sessionInactive }

    private func observeScreenSleep() {
        let center = NSWorkspace.shared.notificationCenter
        func observe(_ name: Notification.Name, _ update: @escaping @MainActor (PortStore) -> Void) {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    update(self)
                    self.monitor?.setPollingPaused(self.isPollingPaused)
                }
            })
        }
        observe(NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        observe(NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        // Fast user switching: another user has the screen.
        observe(NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        // Counters may move while the Mac sleeps; count nothing across it.
        observe(NSWorkspace.didWakeNotification) { $0.nextCaptureAfterGap = true }
        observe(NSWorkspace.willSleepNotification) { $0.flushHistory() }
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
        saveTimer?.invalidate()
        saveTimer = nil
        demoTimer?.invalidate()
        demoTimer = nil
        runningScenario = nil
    }

    /// Re-reads settings that affect data collection (demo mode, demo
    /// scenario, polling, SMC) and rebuilds the snapshot so renamed ports show
    /// at once.
    ///
    /// Switching between live data and demo mode, or between demo scenarios,
    /// is a change of source. The new source starts from scratch, with no
    /// connect or disconnect events, no notifications, no ghosts and a fresh
    /// power history. The history never mixes sources: demo history is
    /// dropped when the source changes, and the live archive is saved and set
    /// aside while demo mode is on and comes back when it ends.
    func applySettings() {
        let wantsDemo = settings.demoMode
        let isDemoRunning = demoTimer != nil
        if isRunning && wantsDemo != isDemoRunning {
            stop()
            switchSource(toDemo: wantsDemo)
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

    /// Entering demo mode saves the live history and sets it aside; leaving
    /// brings it back. Either way the store starts over (`resetForSourceChange`).
    func switchSource(toDemo: Bool) {
        if toDemo {
            flushHistory()
            heldLiveArchive = archive
            archiveHoldsDemo = true
            resetForSourceChange()
        } else {
            resetForSourceChange()
            archive = heldLiveArchive ?? HistoryArchive()
            heldLiveArchive = nil
            archiveHoldsDemo = false
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

    /// Demo pins live under their own key, because demo scenarios use real model ids.
    private var pinStorageKey: String { snapshot.isDemo ? "demo:\(snapshot.machine.model)" : snapshot.machine.model }

    /// This Mac model's pinned port, whether or not the port is in the snapshot.
    var pinnedPortKey: PortKey? { settings.menuBarPinnedPorts[pinStorageKey].flatMap { PortKey($0) } }

    /// Pins `key` to the menu bar for this Mac model (or this demo), or unpins with nil.
    func pinPort(_ key: PortKey?) { settings.menuBarPinnedPorts[pinStorageKey] = key?.description }

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

    // MARK: Events and history

    /// Clears this Mac model's event log, saved copy included.
    func clearEvents() {
        archive.clearEvents(model: snapshot.machine.model)
        events = []
        if !archiveHoldsDemo { eventsDirty = true }
    }

    /// Forgets every saved event, power minute and port counter, for every
    /// Mac model, and deletes the file. In demo mode it clears the demo
    /// history too, and the live history stays cleared when demo mode ends.
    func clearHistory() {
        archive = HistoryArchive()
        if heldLiveArchive != nil { heldLiveArchive = HistoryArchive() }
        events = []
        historyFile?.delete()
        historyIsReadOnly = false
        eventsDirty = false
        powerDirty = false
        refreshHistorySummary()
    }

    /// Turning history off deletes the file (a newer version's too, since the
    /// user asked); this session's history stays in memory and is not saved.
    /// Turning it on loads the file if it was not read at launch.
    func setKeepHistory(_ keep: Bool) {
        settings.keepHistory = keep
        if keep {
            if !archiveHoldsDemo { loadHistoryIfNeeded() }
        } else {
            historyFile?.delete()
            historyIsReadOnly = false
        }
    }

    /// Reads the saved history once, straight into the archive: restored
    /// events never go through `ingest`, so they raise no notifications.
    func loadHistoryIfNeeded() {
        guard !historyLoaded, let historyFile, settings.keepHistory else { return }
        historyLoaded = true
        switch historyFile.load() {
        case .loaded(var saved):
            // Turned on mid-session: keep this session's events, and count no
            // port counters between the file's last capture and now.
            let model = snapshot.machine.model
            saved.append(archive.events(model: model).reversed(), model: model)
            archive = saved
            nextCaptureAfterGap = true
            if hasLoaded { events = archive.events(model: model) }
        case .newerSchema:
            historyIsReadOnly = true
        case .missing, .movedAside:
            break
        }
        refreshHistorySummary()
    }

    /// Saves now if anything changed, for will-sleep and quit, and waits for
    /// a save the timer already queued.
    func flushHistory() {
        if eventsDirty || powerDirty { saveHistory(now: Date(), wait: true) }
        historyFile?.waitForWrites()
    }

    /// The timer's check: new events save within a minute, power alone every
    /// `powerSaveInterval`.
    func saveHistoryIfDue(now: Date = Date()) {
        guard eventsDirty || (powerDirty && now.timeIntervalSince(lastSave) >= Self.powerSaveInterval) else { return }
        saveHistory(now: now, wait: false)
    }

    private func saveHistory(now: Date, wait: Bool) {
        guard let historyFile, historyLoaded, !archiveHoldsDemo, settings.keepHistory, !historyIsReadOnly else { return }
        archive.trim(now: now)
        if wait { historyFile.saveNow(archive) } else { historyFile.save(archive) }
        eventsDirty = false
        powerDirty = false
        lastSave = now
        refreshHistorySummary()
    }

    private func refreshHistorySummary() {
        historySummary = (archiveHoldsDemo ? heldLiveArchive : archive)?.summary ?? HistoryArchive.Summary()
    }

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
        loadHistoryIfNeeded()
        if historyFile != nil {
            let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveHistoryIfDue() }
            }
            RunLoop.main.add(timer, forMode: .common)
            saveTimer = timer
        }
        let monitor = LiveMonitor(configuration: monitorConfiguration)
        self.monitor = monitor
        monitor.setUIVisible(visibleClients > 0)
        monitor.setPollingPaused(isPollingPaused)
        monitor.start { [weak self] raw in
            self?.ingest(raw)
        }
    }

    private func startDemo() {
        // Launching straight into demo mode never reads or writes the file.
        archiveHoldsDemo = true
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
    /// capture is treated as the first one, so it raises no events. The live
    /// archive keeps one section per Mac model, so it stays; a demo archive
    /// starts over, so two scenarios of the same model never mix.
    private func resetForSourceChange() {
        snapshot = .placeholder()
        raw = nil
        history.removeAll()
        allDeparting.removeAll()
        overcurrentBaseline.removeAll()
        events.removeAll()
        hasLoaded = false
        selection = .host
        lastRecordedAt = nil
        nextCaptureAfterGap = true
        if archiveHoldsDemo { archive = HistoryArchive() }
    }

    private func userPortNames(for model: String) -> [String: String] {
        let prefix = "\(model)#"
        var result: [String: String] = [:]
        for (key, value) in settings.portNames where key.hasPrefix(prefix) {
            result[String(key.dropFirst(prefix.count))] = value
        }
        return result
    }

    func ingest(_ raw: RawSnapshot) {
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

        if raw.capturedAt != lastRecordedAt {
            archive.record(built, afterGap: nextCaptureAfterGap)
            nextCaptureAfterGap = false
            lastRecordedAt = raw.capturedAt
            if !built.isDemo { powerDirty = true }
        }

        if overcurrentBaseline.isEmpty {
            for port in built.ports {
                if let count = port.statistics?.overcurrentCount { overcurrentBaseline[port.id] = count }
            }
        }
        built.diagnostics = DiagnosticsEngine.evaluate(built, raw: raw, baseline: overcurrentBaseline)

        let isFirstCapture = !hasLoaded
        let previous = hasLoaded ? snapshot : nil
        let newEvents = SnapshotDiffer.events(from: previous, to: built, at: built.capturedAt)

        trackDeparting(previous: previous, current: built)

        self.raw = raw
        snapshot = built
        history.append(built)
        lastUpdated = built.capturedAt
        hasLoaded = true

        if !newEvents.isEmpty {
            archive.append(newEvents, model: built.machine.model)
            // Demo data is never saved and never raises system notifications.
            if !built.isDemo {
                eventsDirty = true
                onEvents?(newEvents)
            }
        }
        // A count change means `record` dropped events past the age limit.
        if isFirstCapture || !newEvents.isEmpty || events.count != archive.events(model: built.machine.model).count {
            events = archive.events(model: built.machine.model)
        }

        if let selection, !Self.exists(selection, in: built) {
            self.selection = Self.fallback(for: selection, in: built)
        }
    }

    /// Where a selection that `snapshot` no longer has goes: to the dock when
    /// the device (or the device a link led to) is now one of the dock's
    /// built-in parts, else to the Mac.
    static func fallback(for selection: StoreSelection, in snapshot: HostSnapshot) -> StoreSelection {
        switch selection {
        case .device(let id), .link(.device(let id)):
            if let dock = snapshot.dock(withPart: id) { return .device(dock.id) }
            return .host
        default:
            return .host
        }
    }

    /// False when `selection` names a port or device that `snapshot` no
    /// longer has (or a link to one). Displays stay selected; the inspector
    /// says when one is gone.
    private static func exists(_ selection: StoreSelection, in snapshot: HostSnapshot) -> Bool {
        switch selection {
        case .host, .display: return true
        case .port(let key): return snapshot.port(key) != nil
        case .device(let id): return snapshot.device(id: id) != nil
        case .link(let child): return exists(child, in: snapshot)
        }
    }

    /// Records the devices that left between `previous` and `current`, at
    /// any depth, with their parent and position. A device that left with
    /// its parent is part of the parent's ghost, so pulling a hub gives one
    /// ghost (the hub, drawn with its children), not one per device.
    private func trackDeparting(previous: HostSnapshot?, current: HostSnapshot) {
        let now = Date()
        allDeparting.removeAll { now.timeIntervalSince($0.removedAt) > Self.departingLifetime }
        guard let previous else { return }
        // A device that became one of a dock's built-in parts has not left.
        let currentIDs = Set(current.allDevices.map(\.device.id)).union(current.internalPartIDs)
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
