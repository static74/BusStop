import BusStopCore
import Foundation
import Testing
@testable import BusStopApp

/// When `PortStore` writes the widget payload, and when it deletes it.
@MainActor
@Suite("Widget writer")
struct WidgetWriterTests {
    private let start = Date(timeIntervalSince1970: 1_791_115_200)

    private func snapshot(inputMilliwatts: Int, unplugged: Bool = false) -> HostSnapshot {
        var raw = DemoScenario.studioDesk.raw(at: start, tick: 0)
        if unplugged { raw.usbDevices.removeLast() }
        var snapshot = TopologyBuilder.build(raw, options: BuildOptions())
        snapshot.power.systemInputMilliwatts = inputMilliwatts
        return snapshot
    }

    /// `#expect` cannot call a mutating method, so the gate lives in a box.
    @MainActor private final class Gate {
        var gate = WidgetWriteGate()
        func writes(_ snapshot: HostSnapshot, events: [ConnectionEvent] = [], portHealth: [PortKey: PortHealth] = [:],
                    now: Date) -> Bool {
            gate.shouldWrite(snapshot, events: events, portHealth: portHealth, now: now)
        }
    }

    @Test func writesChangesAtOnceAndPowerAtMostOnceAMinute() {
        let gate = Gate()
        let base = snapshot(inputMilliwatts: 62_000)
        #expect(gate.writes(base, now: start))
        #expect(!gate.writes(base, now: start + 1))
        // Within the same whole watt, a minute later: nothing to show.
        #expect(!gate.writes(snapshot(inputMilliwatts: 62_300), now: start + 90))
        // Another watt, but too soon after the last write.
        let morePower = snapshot(inputMilliwatts: 70_000)
        #expect(!gate.writes(morePower, now: start + 30))
        #expect(gate.writes(morePower, now: start + 60))
        // A device leaving shows at once.
        #expect(gate.writes(snapshot(inputMilliwatts: 70_000, unplugged: true), events: [], portHealth: [:],
                                 now: start + 61))
        // So does a new event, and changed port health.
        let event = ConnectionEvent(id: "1", date: start, kind: .deviceDisconnected, title: "Gone", detail: "")
        #expect(gate.writes(morePower, events: [event], portHealth: [:], now: start + 62))
        var health = PortHealth()
        health.errors = 1
        #expect(gate.writes(morePower, events: [event], portHealth: [base.ports[0].key: health], now: start + 63))
    }

    @Test func rewritesBeforeTheWidgetsGoStale() {
        let gate = Gate()
        let base = snapshot(inputMilliwatts: 62_000)
        #expect(gate.writes(base, now: start))
        #expect(!gate.writes(base, now: start + WidgetWriteGate.heartbeat - 1))
        #expect(gate.writes(base, now: start + WidgetWriteGate.heartbeat))
        #expect(WidgetWriteGate.heartbeat < WidgetTimeline.staleAfter)
        // A clock set back does not hold writes off.
        #expect(gate.writes(base, now: start - 3_600))
        gate.gate.reset()
        #expect(gate.writes(base, now: start - 3_600))
    }

    /// A temporary folder and defaults suite, removed when the test ends.
    @MainActor final class Sandbox {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BusStopWidgetWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suite = "BusStopAppTests.Widgets.\(UUID().uuidString)"
        lazy var settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        var file: WidgetPayloadFile { WidgetPayloadFile(url: directory.appending(path: WidgetPayloadFile.fileName)) }
        var reloads = 0

        func store() -> PortStore {
            let store = PortStore(settings: settings, historyFile: HistoryFile(directory: directory), widgetFile: file)
            store.reloadWidgets = { [weak self] in self?.reloads += 1 }
            return store
        }

        deinit {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
    }

    /// A Studio desk capture `seconds` after `start`, its last USB device unplugged when `unplugged` is true.
    private func capture(_ seconds: TimeInterval, unplugged: Bool = false) -> RawSnapshot {
        var raw = DemoScenario.studioDesk.raw(at: start + seconds, tick: 0)
        if unplugged { raw.usbDevices.removeLast() }
        return raw
    }

    /// A store that has seen a device leave, so the payload holds an event.
    private func storeWithEvents(_ sandbox: Sandbox) throws -> PortStore {
        let store = sandbox.store()
        store.loadHistoryIfNeeded()
        store.ingest(capture(0))
        store.ingest(capture(2, unplugged: true))
        #expect(sandbox.reloads == 2)
        let payload = try #require(sandbox.file.read())
        #expect(!payload.events.isEmpty)
        #expect(payload.capturedAt == start + 2)
        #expect(!payload.isDemo)
        return store
    }

    /// A capture with a drive that puts `serial` in its name, and one `seconds` later without it.
    private func driveNamedAfterItsSerial(_ serial: String, unpluggedAfter seconds: TimeInterval) throws
        -> (plugged: RawSnapshot, unplugged: RawSnapshot) {
        var raw = capture(0)
        let index = try #require(raw.usbDevices.firstIndex { $0.node.properties.values["USB Serial Number"] != nil })
        var values = raw.usbDevices[index].node.properties.values
        values["USB Serial Number"] = .string(serial)
        values["USB Product Name"] = .string("Drive \(serial)")
        raw.usbDevices[index].node.properties = PropertyBag(values)
        raw.usbDevices[index].node.name = "Drive \(serial)"
        var unplugged = raw
        unplugged.capturedAt = start + seconds
        unplugged.usbDevices.remove(at: index)
        return (raw, unplugged)
    }

    /// The drive unplugged: the event names it, but the snapshot the payload is built
    /// from no longer has its serial.
    @Test func unpluggedDeviceSerialStaysOutOfThePayload() throws {
        let serial = "SNXYZ123"
        let (raw, unplugged) = try driveNamedAfterItsSerial(serial, unpluggedAfter: 2)
        let sandbox = Sandbox()
        let store = sandbox.store()
        store.loadHistoryIfNeeded()
        store.ingest(raw)
        store.ingest(unplugged)
        #expect(store.events.contains { $0.title.contains(serial) })
        let payload = try #require(sandbox.file.read())
        #expect(payload.events.contains { $0.kind == .deviceDisconnected })
        let json = String(decoding: try Data(contentsOf: sandbox.file.url), as: UTF8.self)
        #expect(!json.contains(serial))
    }

    /// The drive unplugged, then Bus Stop quit: the next launch reads the event back
    /// from the history but never sees the drive.
    @Test func unpluggedDeviceSerialStaysOutAfterARelaunch() throws {
        let serial = "SNXYZ123"
        let (raw, unplugged) = try driveNamedAfterItsSerial(serial, unpluggedAfter: 2)
        let sandbox = Sandbox()
        let first = sandbox.store()
        first.loadHistoryIfNeeded()
        first.ingest(raw)
        first.ingest(unplugged)
        first.flushHistory()

        let second = sandbox.store()
        second.loadHistoryIfNeeded()
        var later = unplugged
        later.capturedAt = start + 60
        second.ingest(later)
        #expect(second.events.contains { $0.title.contains(serial) })
        let json = String(decoding: try Data(contentsOf: sandbox.file.url), as: UTF8.self)
        #expect(json.contains("disconnected"))
        #expect(!json.contains(serial))
    }

    @Test func clearHistoryDeletesThePayload() throws {
        let sandbox = Sandbox()
        let store = try storeWithEvents(sandbox)
        store.clearHistory()
        #expect(sandbox.file.read() == nil)
        #expect(sandbox.reloads == 3)
        // The next capture writes a fresh payload, without the cleared events.
        store.ingest(capture(4, unplugged: true))
        #expect(sandbox.file.read()?.events.isEmpty == true)
    }

    @Test func turningHistoryOffDeletesThePayloadAndKeepsEventsOut() throws {
        let sandbox = Sandbox()
        let store = try storeWithEvents(sandbox)
        store.setKeepHistory(false)
        #expect(sandbox.file.read() == nil)
        store.ingest(capture(4, unplugged: true))
        let payload = try #require(sandbox.file.read())
        #expect(payload.events.isEmpty)
        #expect(payload.dayPower.isEmpty)
        #expect(!store.events.isEmpty)
    }

    /// History off at launch, then turned on: the next capture writes the history in, though nothing else changed.
    @Test func turningHistoryOnWritesItAtTheNextCapture() throws {
        let sandbox = Sandbox()
        sandbox.settings.keepHistory = false
        let store = sandbox.store()
        store.ingest(capture(0))
        #expect(try #require(sandbox.file.read()).portDays == nil)
        store.setKeepHistory(true)
        store.ingest(capture(2))
        #expect(try #require(sandbox.file.read()).portDays != nil)
    }

    /// Demo power moves on every 2-second tick; the payload follows at most once a minute.
    @Test func movingPowerAloneWritesRarely() {
        let sandbox = Sandbox()
        let store = sandbox.store()
        for tick in 0..<20 {
            store.ingest(DemoScenario.studioDesk.raw(at: start + Double(tick * 2), tick: tick))
        }
        #expect(sandbox.reloads == 1)
    }

    @Test func noWidgetFileWritesNothing() {
        let sandbox = Sandbox()
        let store = PortStore(settings: sandbox.settings)
        store.reloadWidgets = { Issue.record("reloaded without a widget file") }
        store.ingest(DemoScenario.studioDesk.raw(at: start, tick: 0))
        store.clearHistory()
        #expect(!FileManager.default.fileExists(atPath: sandbox.file.url.path))
    }
}
