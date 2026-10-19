import AppKit
import BusStopCore
import Foundation
import Testing
@testable import BusStopApp

/// `PortStore` saving and restoring history.json. Every test uses its own
/// temporary folder and defaults suite, feeds demo captures through `ingest`
/// as if they were live, and never starts the live monitor.
@MainActor
@Suite("History store")
struct HistoryStoreTests {
    private let start = Date(timeIntervalSince1970: 1_791_115_200)

    /// A temporary folder and defaults suite, removed when the test ends.
    @MainActor final class Sandbox {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BusStopHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suite = "BusStopAppTests.History.\(UUID().uuidString)"
        lazy var settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        var file: HistoryFile { HistoryFile(directory: directory) }

        func store() -> PortStore { PortStore(settings: settings, historyFile: file) }

        func names() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
        }

        func data() -> Data? { try? Data(contentsOf: file.url) }

        deinit {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
    }

    /// A Studio desk capture `seconds` after `start`, with its last leaf USB
    /// device unplugged when `unplugged` is true.
    private func capture(_ seconds: TimeInterval, unplugged: Bool = false,
                         scenario: DemoScenario = .studioDesk) -> RawSnapshot {
        var raw = scenario.raw(at: start.addingTimeInterval(seconds), tick: 0)
        if unplugged {
            let parents = Set(raw.usbDevices.compactMap(\.parentDeviceID))
            let leaf = raw.usbDevices.last { !parents.contains($0.id) }?.id
            raw.usbDevices.removeAll { $0.id == leaf }
        }
        return raw
    }

    /// A store that has loaded history and seen a device leave, saved to disk.
    private func storeWithSavedEvents(_ sandbox: Sandbox) -> PortStore {
        let store = sandbox.store()
        store.loadHistoryIfNeeded()
        store.ingest(capture(0))
        store.ingest(capture(2, unplugged: true))
        store.flushHistory()
        return store
    }

    @Test func eventsSurviveARelaunch() throws {
        let sandbox = Sandbox()
        let first = storeWithSavedEvents(sandbox)
        #expect(!first.events.isEmpty)
        #expect(first.historySummary.eventCount == first.events.count)

        let relaunched = sandbox.store()
        relaunched.loadHistoryIfNeeded()
        #expect(relaunched.historySummary.eventCount == first.events.count)
        relaunched.ingest(capture(3_600))
        #expect(relaunched.events == first.events)
    }

    @Test func savedOvercurrentWarnsAfterARelaunch() throws {
        let sandbox = Sandbox()
        let raw = capture(3_600)
        let port = try #require(TopologyBuilder.build(raw, options: BuildOptions()).ports.first)
        var archive = HistoryArchive()
        archive.sections[raw.machine.model, default: HistoryArchive.Section()].lastOvercurrentAt[port.id] = start
        sandbox.file.saveNow(archive)

        let relaunched = sandbox.store()
        var raised: [ConnectionEvent] = []
        relaunched.onEvents = { raised += $0 }
        relaunched.loadHistoryIfNeeded()
        relaunched.ingest(raw)
        #expect(relaunched.snapshot.diagnostics.map(\.id).contains("overcurrent:\(port.id)"))
        #expect(raised.isEmpty)
    }

    @Test func restoredEventsDoNotNotify() {
        let sandbox = Sandbox()
        _ = storeWithSavedEvents(sandbox)
        let relaunched = sandbox.store()
        var notified: [ConnectionEvent] = []
        relaunched.onEvents = { notified += $0 }
        relaunched.loadHistoryIfNeeded()
        relaunched.ingest(capture(3_600))
        #expect(!relaunched.events.isEmpty)
        #expect(notified.isEmpty)
    }

    @Test func reIngestingTheSameCaptureRecordsNothing() {
        let sandbox = Sandbox()
        let store = sandbox.store()
        let raw = capture(0)
        store.ingest(raw)
        // Renaming a port or changing a setting re-ingests the same capture.
        store.ingest(raw)
        store.renamePort(PortKey(type: PortKey.usbCType, number: 1), to: "Desk")
        #expect(store.archive.sections[raw.machine.model]?.pendingPower.count == 1)
    }

    @Test func reIngestingTheSameCaptureDoesNotAdvanceHealth() throws {
        let sandbox = Sandbox()
        let store = sandbox.store()
        store.ingest(capture(0))
        for t in stride(from: 20.0, through: 40, by: 10) {
            store.ingest(capture(t))
            store.ingest(capture(t + 5, unplugged: true))
        }
        store.ingest(capture(50))
        let finding = try #require(store.snapshot.diagnostics.first { $0.kind == .flakyConnection })
        let deviceID = try #require(finding.deviceID)
        #expect(store.connectionHistory(ofDevice: deviceID)?.cycles == 3)

        // Settings changes re-ingest the same capture: the finding stays and nothing more is counted.
        store.applySettings()
        store.renamePort(PortKey(type: PortKey.usbCType, number: 1), to: "Desk")
        #expect(store.snapshot.diagnostics.contains { $0.id == finding.id })
        #expect(store.connectionHistory(ofDevice: deviceID)?.cycles == 3)
    }

    /// A device that keeps dropping out stays selected while it is gone, so
    /// its inspector (and Connection history) is there again when it returns.
    @Test func aDeviceThatDropsOutStaysSelected() throws {
        let sandbox = Sandbox()
        let store = sandbox.store()
        // flakyCable unplugs the iPhone on tick 2 of every 4.
        func tick(_ n: Int) {
            store.ingest(DemoScenario.flakyCable.raw(at: start.addingTimeInterval(Double(n) * 2), tick: n))
        }
        tick(0)
        let iPhone = try #require(store.snapshot.allDevices.first { $0.device.name == "iPhone" }?.device.id)
        store.selection = .device(iPhone)
        tick(1)
        tick(2)
        #expect(store.snapshot.device(id: iPhone) == nil)
        #expect(store.selection == .device(iPhone))
        tick(3)
        #expect(store.snapshot.device(id: iPhone) != nil)
        #expect(store.selection == .device(iPhone))
    }

    @Test func aClockSetBackIsAGapForHealth() {
        let sandbox = Sandbox()
        let store = sandbox.store()
        store.ingest(capture(0))
        store.ingest(capture(100))
        // The clock goes back 50 s: the drops that follow fall in the settle time after a gap.
        for t in stride(from: 50.0, through: 62, by: 6) {
            store.ingest(capture(t, unplugged: true))
            store.ingest(capture(t + 3))
        }
        #expect(!store.snapshot.diagnostics.contains { $0.kind == .flakyConnection })
    }

    @Test func capturesBeforeTheWakeNotificationAreGaps() {
        let sandbox = Sandbox()
        let store = sandbox.store()
        let center = NSWorkspace.shared.notificationCenter
        store.ingest(capture(0))
        store.ingest(capture(100))
        // Observers use the main queue, so a post from the main thread runs them inline.
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        // The device re-enumerates on wake before didWake arrives.
        for t in stride(from: 200.0, through: 240, by: 20) {
            store.ingest(capture(t, unplugged: true))
            store.ingest(capture(t + 10))
        }
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(!store.snapshot.diagnostics.contains { $0.kind == .flakyConnection })
    }

    @Test func aDeviceBackWithTheScreensIsNotACycle() {
        // A monitor that drops off while the screens sleep comes back when they wake.
        let sandbox = Sandbox()
        let store = sandbox.store()
        let center = NSWorkspace.shared.notificationCenter
        store.ingest(capture(0))
        store.ingest(capture(100))
        for i in 0..<3 {
            let t = 200 + Double(i) * 120
            center.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            store.ingest(capture(t, unplugged: true))
            center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            store.ingest(capture(t + 60))
        }
        #expect(!store.snapshot.diagnostics.contains { $0.kind == .flakyConnection })
    }

    @Test func launchingInDemoLeavesTheFileByteIdentical() throws {
        let sandbox = Sandbox()
        _ = storeWithSavedEvents(sandbox)
        let before = try #require(sandbox.data())

        sandbox.settings.demoMode = true
        let demo = sandbox.store()
        demo.start()
        demo.refresh()
        demo.ingest(capture(4, unplugged: true))
        #expect(!demo.events.isEmpty)
        demo.clearEvents()
        demo.saveHistoryIfDue(now: start.addingTimeInterval(86_400))
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        demo.flushHistory()
        demo.stop()

        #expect(sandbox.data() == before)
        #expect(sandbox.names() == ["history.json"])
    }

    @Test func leavingDemoRestoresLiveHistory() throws {
        let sandbox = Sandbox()
        let store = storeWithSavedEvents(sandbox)
        let liveEvents = store.events
        let saved = try #require(sandbox.data())

        sandbox.settings.demoMode = true
        store.switchSource(toDemo: true)
        store.ingest(capture(10))
        store.ingest(capture(12, unplugged: true))
        #expect(!store.events.isEmpty)
        #expect(store.events != liveEvents)
        // Settings keep describing the live history.
        #expect(store.historySummary.eventCount == liveEvents.count)
        store.flushHistory()
        #expect(sandbox.data() == saved)

        sandbox.settings.demoMode = false
        store.switchSource(toDemo: false)
        store.ingest(capture(20))
        #expect(store.events == liveEvents)
    }

    @Test func demoScenariosWithOneModelDoNotMix() {
        let sandbox = Sandbox()
        sandbox.settings.demoMode = true
        let store = sandbox.store()
        store.start()
        defer { store.stop() }
        store.ingest(capture(2, unplugged: true))
        #expect(!store.events.isEmpty)

        // Another scenario and back is a change of source each time.
        sandbox.settings.demoScenario = .travel
        store.refresh()
        sandbox.settings.demoScenario = .studioDesk
        store.refresh()
        #expect(store.events.isEmpty)
        #expect(store.archive.events(model: DemoScenario.studioDesk.model).isEmpty)
    }

    @Test func clearHistoryEmptiesTheFile() {
        let sandbox = Sandbox()
        let store = storeWithSavedEvents(sandbox)
        store.clearHistory()
        #expect(store.events.isEmpty)
        #expect(store.historySummary == HistoryArchive.Summary())
        #expect(sandbox.names().isEmpty)

        let relaunched = sandbox.store()
        relaunched.loadHistoryIfNeeded()
        relaunched.ingest(capture(3_600))
        #expect(relaunched.events.isEmpty)
    }

    @Test func clearHistoryInDemoStaysClearedAfterDemo() {
        let sandbox = Sandbox()
        let store = storeWithSavedEvents(sandbox)
        sandbox.settings.demoMode = true
        store.switchSource(toDemo: true)
        store.ingest(capture(10))
        store.clearHistory()
        #expect(sandbox.names().isEmpty)

        sandbox.settings.demoMode = false
        store.switchSource(toDemo: false)
        store.ingest(capture(20))
        #expect(store.events.isEmpty)
        store.ingest(capture(22, unplugged: true))
        #expect(!store.events.isEmpty)
        store.flushHistory()

        let relaunched = sandbox.store()
        relaunched.loadHistoryIfNeeded()
        relaunched.ingest(capture(3_600))
        #expect(relaunched.events == store.events)
    }

    @Test func turningKeepHistoryOffDeletesTheFile() throws {
        let sandbox = Sandbox()
        let store = storeWithSavedEvents(sandbox)
        try Data("x".utf8).write(to: sandbox.directory.appending(path: "history-corrupt-1.json"))
        try Data("x".utf8).write(to: sandbox.directory.appending(path: "notes.txt"))

        store.setKeepHistory(false)
        #expect(!sandbox.settings.keepHistory)
        #expect(sandbox.names() == ["notes.txt"])
        // The session keeps its history in memory but never saves it.
        store.ingest(capture(4))
        store.ingest(capture(6, unplugged: true))
        #expect(!store.events.isEmpty)
        store.flushHistory()
        #expect(sandbox.names() == ["notes.txt"])
    }

    @Test func turningKeepHistoryOffDeletesANewerVersionsFile() throws {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(at: sandbox.directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion": 99, "sections": {}}"#.utf8).write(to: sandbox.file.url)
        let store = sandbox.store()
        store.loadHistoryIfNeeded()
        #expect(store.historyIsReadOnly)
        store.setKeepHistory(false)
        #expect(!store.historyIsReadOnly)
        #expect(sandbox.names().isEmpty)
    }

    @Test func keepHistoryOffSkipsLoading() {
        let sandbox = Sandbox()
        _ = storeWithSavedEvents(sandbox)
        sandbox.settings.keepHistory = false
        let relaunched = sandbox.store()
        relaunched.loadHistoryIfNeeded()
        relaunched.ingest(capture(3_600))
        #expect(relaunched.events.isEmpty)
        #expect(sandbox.data() != nil)
    }

    @Test func turningKeepHistoryOnMidSessionKeepsThisSessionsEvents() throws {
        let sandbox = Sandbox()
        let saved = storeWithSavedEvents(sandbox).events
        sandbox.settings.keepHistory = false
        let store = sandbox.store()
        store.loadHistoryIfNeeded()
        store.ingest(capture(3_600))
        store.ingest(capture(3_602, unplugged: true))
        let session = store.events
        #expect(!session.isEmpty)

        // Reset All Settings takes this path too.
        store.setKeepHistory(true)
        #expect(store.events == session + saved)
        store.flushHistory()
        let relaunched = sandbox.store()
        relaunched.loadHistoryIfNeeded()
        relaunched.ingest(capture(7_200))
        #expect(relaunched.events == session + saved)
    }

    @Test func turningKeepHistoryOffAndOnNeverWritesTheDeletedHistoryBack() {
        let sandbox = Sandbox()
        let store = storeWithSavedEvents(sandbox)
        let deleted = Set(store.events.map(\.id))
        #expect(!deleted.isEmpty)
        store.setKeepHistory(false)
        store.setKeepHistory(true)
        #expect(store.events.isEmpty)
        store.ingest(capture(4))
        store.flushHistory()
        #expect(sandbox.data() != nil)

        let relaunched = sandbox.store()
        relaunched.loadHistoryIfNeeded()
        #expect(deleted.isDisjoint(with: relaunched.events.map(\.id)))
    }

    @Test func eventsSaveAtMostEveryFiveMinutes() throws {
        let sandbox = Sandbox()
        let store = sandbox.store()
        store.loadHistoryIfNeeded()
        store.ingest(capture(0))
        store.ingest(capture(2, unplugged: true))
        store.saveHistoryIfDue(now: start)
        store.historyFile?.waitForWrites()
        let saved = try #require(sandbox.data())

        store.ingest(capture(60))
        store.saveHistoryIfDue(now: start.addingTimeInterval(PortStore.eventSaveInterval - 60))
        store.historyFile?.waitForWrites()
        #expect(sandbox.data() == saved)
        store.saveHistoryIfDue(now: start.addingTimeInterval(PortStore.eventSaveInterval))
        store.historyFile?.waitForWrites()
        #expect(sandbox.data() != saved)
    }

    @Test func expiredEventsLeaveTheEventsPage() {
        let sandbox = Sandbox()
        let store = storeWithSavedEvents(sandbox)
        #expect(!store.events.isEmpty)
        // No new events, but the old ones are now past the 30-day limit.
        store.ingest(capture(HistoryArchive.eventAge + 60, unplugged: true))
        // A step forward of more than a day holds off the age trim until the clock has held for a day.
        #expect(!store.events.isEmpty)
        store.ingest(capture(HistoryArchive.eventAge + 60 + HistoryArchive.clockTrust, unplugged: true))
        #expect(store.events.isEmpty)
    }

    @Test func powerAloneSavesEveryFifteenMinutes() throws {
        let sandbox = Sandbox()
        let store = sandbox.store()
        store.loadHistoryIfNeeded()
        store.ingest(capture(0))
        store.ingest(capture(2, unplugged: true))
        store.saveHistoryIfDue(now: start)
        store.historyFile?.waitForWrites()
        let saved = try #require(sandbox.data())

        store.ingest(capture(60, unplugged: true))
        // flushHistory would save the power change, so only wait for queued writes.
        store.saveHistoryIfDue(now: start.addingTimeInterval(PortStore.powerSaveInterval - 60))
        store.historyFile?.waitForWrites()
        #expect(sandbox.data() == saved)
        store.saveHistoryIfDue(now: start.addingTimeInterval(PortStore.powerSaveInterval))
        store.historyFile?.waitForWrites()
        #expect(sandbox.data() != saved)
    }

    @Test func corruptFileIsMovedAside() throws {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(at: sandbox.directory, withIntermediateDirectories: true)
        let garbage = Data(#"{"schemaVersion": 1, "sections": {"Mac"#.utf8)
        try garbage.write(to: sandbox.file.url)

        let store = sandbox.store()
        store.loadHistoryIfNeeded()
        let names = sandbox.names()
        #expect(names.count == 1)
        let aside = try #require(names.first)
        #expect(aside.hasPrefix("history-corrupt-"))
        #expect(try Data(contentsOf: sandbox.directory.appending(path: aside)) == garbage)

        store.ingest(capture(0))
        store.ingest(capture(2, unplugged: true))
        store.flushHistory()
        #expect(sandbox.names() == ["history.json", aside].sorted())
    }

    @Test func aCorruptFileThatCannotBeMovedIsNeverOverwritten() throws {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(at: sandbox.directory, withIntermediateDirectories: true)
        let garbage = Data(#"{"schemaVersion": 1, "sections": {"Mac"#.utf8)
        try garbage.write(to: sandbox.file.url)
        // A read-only folder makes the rename fail.
        let manager = FileManager.default
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: sandbox.directory.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sandbox.directory.path) }

        let store = sandbox.store()
        store.loadHistoryIfNeeded()
        #expect(sandbox.names() == ["history.json"])
        store.ingest(capture(0))
        store.ingest(capture(2, unplugged: true))
        store.flushHistory()
        store.saveHistoryIfDue(now: start.addingTimeInterval(86_400))
        store.historyFile?.waitForWrites()
        #expect(sandbox.data() == garbage)

        // Clear History deletes the file, and saving starts again.
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sandbox.directory.path)
        store.clearHistory()
        #expect(sandbox.names().isEmpty)
        store.ingest(capture(4))
        store.flushHistory()
        #expect(sandbox.names() == ["history.json"])
    }

    @Test func newerSchemaFileIsNeverOverwritten() throws {
        let sandbox = Sandbox()
        try FileManager.default.createDirectory(at: sandbox.directory, withIntermediateDirectories: true)
        let newer = Data(#"{"schemaVersion": 2, "sections": {}}"#.utf8)
        try newer.write(to: sandbox.file.url)

        let store = sandbox.store()
        store.loadHistoryIfNeeded()
        #expect(store.historyIsReadOnly)
        store.ingest(capture(0))
        store.ingest(capture(2, unplugged: true))
        store.flushHistory()
        store.saveHistoryIfDue(now: start.addingTimeInterval(86_400))
        #expect(sandbox.data() == newer)
    }

    @Test func fileIsPrivateToTheUser() throws {
        let sandbox = Sandbox()
        _ = storeWithSavedEvents(sandbox)
        let file = try FileManager.default.attributesOfItem(atPath: sandbox.file.url.path)
        let folder = try FileManager.default.attributesOfItem(atPath: sandbox.directory.path)
        #expect((file[.posixPermissions] as? Int) == 0o600)
        #expect((folder[.posixPermissions] as? Int) == 0o700)
    }

    @Test func resetAllRestoresKeepHistory() {
        let sandbox = Sandbox()
        sandbox.settings.keepHistory = false
        #expect(AppSettings(defaults: UserDefaults(suiteName: sandbox.suite)!).keepHistory == false)
        sandbox.settings.resetAll()
        #expect(sandbox.settings.keepHistory)
        #expect(AppSettings.Key.all.contains(AppSettings.Key.keepHistory))
    }
}
