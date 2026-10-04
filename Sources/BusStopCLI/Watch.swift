import BusStopCore
import Foundation

/// `busstop --watch`: prints one line per `ConnectionEvent` until SIGINT or
/// SIGTERM.
///
/// Live mode is driven by `LiveMonitor`; demo mode by a two-second ticker.
/// Every capture goes through the same pipeline as a one-shot run, and
/// `SnapshotDiffer` compares it with the previous one. Event lines go to
/// standard output; the start and stop notices go to standard error so they
/// never mix with `--json` lines.
///
/// Unless `--no-redact` is given, every event passes through
/// `Exporter.redacted(_:)` first, so display serial numbers and other unit
/// identifiers stay out of both output formats. Text lines also pass names
/// through `Format.terminalSafe`, because device-supplied names could
/// otherwise carry terminal escape sequences.
@MainActor
final class WatchSession {
    /// Demo ticker interval, matching the app's demo mode.
    static let demoInterval: Duration = .seconds(2)

    private let options: CLIOptions
    private var previous: HostSnapshot?
    private var baseline: [String: Int] = [:]
    private var eventCount = 0
    private var stopMonitoring: (@Sendable () -> Void)?
    private var demoTask: Task<Void, Never>?
    private let timeFormatter: DateFormatter
    private let lineEncoder: JSONEncoder

    init(options: CLIOptions) {
        self.options = options
        timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = TimeZone.current
        timeFormatter.dateFormat = "HH:mm:ss"
        lineEncoder = JSONEncoder()
        lineEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        lineEncoder.dateEncodingStrategy = .iso8601
    }

    /// Starts watching, installs the signal handlers and never returns.
    static func run(_ options: CLIOptions) -> Never {
        let session = WatchSession(options: options)

        // Handle Control-C and `kill` on the main queue instead of letting the
        // default action end the process mid-line.
        let signalSources = [SIGINT, SIGTERM].map { number -> DispatchSourceSignal in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { session.stop() }
            }
            source.resume()
            return source
        }

        session.start()
        // Keep the signal sources alive for as long as the process runs.
        withExtendedLifetime(signalSources) {
            runMainRunLoop()
        }
    }

    /// Runs the main run loop until the process exits.
    ///
    /// This takes the place of `dispatchMain()`: `LiveMonitor` registers its
    /// power-source and display-change callbacks on the main run loop, which
    /// `dispatchMain()` never runs. The main run loop also drains the main
    /// dispatch queue, so main-actor work and the signal handlers still run.
    /// The timer only keeps the run loop from returning when it has no other
    /// sources (demo mode).
    private static func runMainRunLoop() -> Never {
        let keepAlive = Timer(fire: .distantFuture, interval: 0, repeats: false) { _ in }
        RunLoop.main.add(keepAlive, forMode: .default)
        while true {
            _ = RunLoop.main.run(mode: .default, before: .distantFuture)
        }
    }

    private func start() {
        switch options.source {
        case .live:
            stopMonitoring = LiveSource.startMonitoring(includeSMC: options.includeSMC) { [weak self] raw in
                self?.ingest(raw, isDemo: false)
            }
        case .demo(let scenario):
            demoTask = Task { [weak self] in
                var tick = 0
                while !Task.isCancelled {
                    self?.ingest(DemoWatch.raw(scenario, tick: tick, at: Date()), isDemo: true)
                    tick += 1
                    try? await Task.sleep(for: WatchSession.demoInterval)
                }
            }
        case .file:
            // Rejected by the argument parser; nothing to watch.
            Console.fail(CLIFailure.usage("--watch needs this Mac or --demo"))
        }
    }

    /// Builds a snapshot from a capture and prints the events since the
    /// previous one.
    private func ingest(_ raw: RawSnapshot, isDemo: Bool) {
        let isFirst = previous == nil
        if isFirst {
            // Overcurrent counts are compared with the start of the session.
            baseline = Pipeline.overcurrentBaseline(of: Pipeline.snapshot(from: raw, isDemo: isDemo))
        }
        let snapshot = Pipeline.snapshot(from: raw, isDemo: isDemo, baseline: baseline)
        if isFirst { announce(snapshot) }
        var events = SnapshotDiffer.events(from: previous, to: snapshot, at: snapshot.capturedAt)
        if options.redact { events = events.map { Exporter.redacted($0) } }
        previous = snapshot
        for event in events {
            eventCount += 1
            Console.out(line(for: event) + "\n")
        }
    }

    /// "Watching MacBook Pro (demo: Studio desk): 4 ports, 6 devices. Press Control-C to stop."
    ///
    /// For a demo setup with nothing to unplug, a second line says that no
    /// events will appear.
    private func announce(_ snapshot: HostSnapshot) {
        var subject = Format.terminalSafe(snapshot.machine.name)
        if case .demo(let scenario) = options.source { subject += " (demo: \(scenario.title))" }
        let ports = snapshot.ports.count
        let devices = snapshot.deviceCount
        Console.err("Watching \(subject): \(ports) \(ports == 1 ? "port" : "ports"), "
            + "\(devices) \(devices == 1 ? "device" : "devices"). Press Control-C to stop.\n")
        if case .demo(let scenario) = options.source, !DemoWatch.hasRemovableDevice(scenario) {
            Console.err(DemoWatch.nothingToUnplugNotice)
        }
    }

    /// One output line: a JSON object with `--json`, otherwise
    /// "14:03:12 + Samsung T9 connected · Left Front · USB-C · USB 3.2 Gen 2 @ 10 Gb/s".
    ///
    /// The title and detail of a text line go through `Format.terminalSafe`:
    /// they hold device-supplied names, which must not be able to break the
    /// line or send escape sequences to the terminal. JSON needs no such step,
    /// because `JSONEncoder` escapes control characters.
    func line(for event: ConnectionEvent) -> String {
        if options.format == .json {
            if let data = try? lineEncoder.encode(event), let text = String(data: data, encoding: .utf8) {
                return text
            }
            return #"{"error":"could not encode event"}"#
        }
        var text = "\(timeFormatter.string(from: event.date)) \(Self.marker(for: event)) \(Format.terminalSafe(event.title))"
        let detail = Format.terminalSafe(event.detail)
        if !detail.isEmpty { text += " · \(detail)" }
        return text
    }

    /// A one-character hint at the start of each line.
    static func marker(for event: ConnectionEvent) -> String {
        switch event.kind {
        case .deviceConnected, .chargerConnected, .displayConnected: return "+"
        case .deviceDisconnected, .chargerDisconnected, .displayDisconnected: return "-"
        case .linkChanged: return event.isDowngrade ? "↓" : "↑"
        case .diagnosticRaised: return "!"
        }
    }

    /// Stops monitoring, prints a summary to standard error and exits.
    func stop() {
        stopMonitoring?()
        stopMonitoring = nil
        demoTask?.cancel()
        let noun = eventCount == 1 ? "event" : "events"
        Console.err("\nStopped after \(eventCount) \(noun).\n")
        exit(ExitStatus.success)
    }
}

/// Demo data for `--watch`.
///
/// Demo scenarios describe a fixed setup, so on their own they would never
/// produce an event. To show what watching looks like, one sample device is
/// unplugged for two ticks and plugged back in for two ticks, in a loop.
/// A scenario with no USB devices (`unplugged`) has nothing to unplug, so
/// the session says so on standard error instead of staying silent.
enum DemoWatch {
    /// Ticks the sample device stays in each state.
    static let ticksPerPhase = 2

    /// Printed to standard error when the demo setup has no device that
    /// `raw(_:tick:at:)` can unplug.
    static let nothingToUnplugNotice =
        "This demo setup has nothing plugged in, so no events will appear. Try --demo studioDesk.\n"

    static func raw(_ scenario: DemoScenario, tick: Int, at date: Date) -> RawSnapshot {
        var raw = scenario.raw(at: date, tick: tick)
        let unplugged = (tick / ticksPerPhase) % 2 == 1
        if unplugged, let id = removableDeviceID(in: raw) {
            raw.usbDevices.removeAll { $0.id == id }
        }
        return raw
    }

    /// True when the scenario has a device that `raw(_:tick:at:)` unplugs, so
    /// watching it produces events.
    static func hasRemovableDevice(_ scenario: DemoScenario) -> Bool {
        removableDeviceID(in: scenario.raw(at: Date(), tick: 0)) != nil
    }

    /// The last USB device that has no devices below it, so removing it never
    /// orphans another record.
    static func removableDeviceID(in raw: RawSnapshot) -> UInt64? {
        let parents = Set(raw.usbDevices.compactMap(\.parentDeviceID))
        return raw.usbDevices.last { !parents.contains($0.id) }?.id
    }
}
