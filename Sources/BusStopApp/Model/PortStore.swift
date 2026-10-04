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
    var device: DeviceNode
    var portKey: PortKey?
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
    private(set) var departing: [DepartingDevice] = []
    var selection: StoreSelection? = .host
    /// Bumped by `reveal(_:)`. The topology window watches it to navigate to
    /// the selection (switch sidebar section, scroll the graph, show the
    /// inspector) even when the selection itself did not change.
    private(set) var revealGeneration = 0

    /// Called with the events of each refresh (used for notifications).
    @ObservationIgnored var onEvents: (([ConnectionEvent]) -> Void)?

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored private var monitor: LiveMonitor?
    @ObservationIgnored private var demoTimer: Timer?
    @ObservationIgnored private var demoTick = 0
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
    }

    /// Re-reads settings that affect data collection (demo mode, polling,
    /// SMC) and rebuilds the snapshot so renamed ports show at once.
    func applySettings() {
        let wantsDemo = settings.demoMode
        let isDemoRunning = demoTimer != nil
        if isRunning && wantsDemo != isDemoRunning {
            stop()
            resetForSourceChange()
            start()
            return
        }
        if wantsDemo {
            ingest(settings.demoScenario.raw(at: Date(), tick: demoTick))
        } else {
            monitor?.update(configuration: monitorConfiguration)
            if let raw { ingest(raw) }
        }
    }

    func refresh() {
        if settings.demoMode {
            demoTick += 1
            ingest(settings.demoScenario.raw(at: Date(), tick: demoTick))
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
    var visiblePorts: [PhysicalPort] {
        var ports = snapshot.ports
        if settings.hideEmptyPorts { ports = ports.filter(\.isConnected) }
        if settings.portOrder == .connectedFirst {
            ports = ports.filter(\.isConnected) + ports.filter { !$0.isConnected }
        }
        return ports
    }

    /// Selects `selection` and asks the topology window to bring it into view.
    func reveal(_ selection: StoreSelection) {
        self.selection = selection
        revealGeneration += 1
    }

    func departing(on key: PortKey?) -> [DepartingDevice] {
        departing.filter { $0.portKey == key }
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
        ingest(settings.demoScenario.raw(at: Date(), tick: demoTick))
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.demoTick += 1
                self.ingest(self.settings.demoScenario.raw(at: Date(), tick: self.demoTick))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        demoTimer = timer
    }

    private func resetForSourceChange() {
        snapshot = .placeholder()
        raw = nil
        history.removeAll()
        departing.removeAll()
        overcurrentBaseline.removeAll()
        hasLoaded = false
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
            onEvents?(newEvents)
        }

        if case .port(let key)? = selection, built.port(key) == nil { selection = .host }
        if case .device(let id)? = selection, built.device(id: id) == nil { selection = .host }
    }

    private func trackDeparting(previous: HostSnapshot?, current: HostSnapshot) {
        let now = Date()
        departing.removeAll { now.timeIntervalSince($0.removedAt) > Self.departingLifetime }
        guard let previous else { return }
        let currentIDs = Set(current.allDevices.map(\.device.id))
        // Devices that came back are no longer departing.
        departing.removeAll { currentIDs.contains($0.id) }
        for entry in previous.allDevices where entry.depth == 0 && !currentIDs.contains(entry.device.id) {
            guard !departing.contains(where: { $0.id == entry.device.id }) else { continue }
            departing.append(DepartingDevice(device: entry.device, portKey: entry.port?.key, removedAt: now))
        }
        if !departing.isEmpty {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.departingLifetime + 0.1))
                guard let self else { return }
                let cutoff = Date()
                self.departing.removeAll { cutoff.timeIntervalSince($0.removedAt) > Self.departingLifetime }
            }
        }
    }
}
