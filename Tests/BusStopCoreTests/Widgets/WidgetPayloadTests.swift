import Foundation
import Testing
@testable import BusStopCore

@Suite("Widget payload")
struct WidgetPayloadTests {
    typealias S = DemoTestSupport

    /// Measured on 2026-10-26: 74 KB (dock station) to 153 KB (studio desk), most of it power samples.
    static let sizeLimit = 256 * 1024

    /// The largest payload the app writes for `scenario`: a full 10-minute
    /// buffer at the 1-second poll, a full day of 5-minute steps, an event per
    /// device (more than the limit) and port health for every port.
    static func fullPayload(_ scenario: DemoScenario) -> WidgetPayload {
        let snapshot = S.snapshot(scenario)
        let sample = PowerSample(snapshot)
        func samples(_ count: Int, step: TimeInterval) -> [PowerSample] {
            (0..<count).map { index in
                var copy = sample
                copy.date = snapshot.capturedAt - Double(count - index) * step
                return copy
            }
        }
        let devices = snapshot.allDevices
        let events = (0..<25).map { index in
            let entry = devices.isEmpty ? nil : devices[index % devices.count]
            let id = entry?.device.id ?? "usb:01100000:5ac:1460"
            return ConnectionEvent(id: "\(index):\(id)", date: snapshot.capturedAt - Double(index),
                                   kind: .deviceConnected, title: "\(entry?.device.name ?? "A drive") connected",
                                   detail: "\(entry?.port?.label.location ?? "Other") · \(entry?.device.serialNumber ?? "")",
                                   portKey: entry?.port?.key, deviceID: id, subjectID: id)
        }
        var health = PortHealth()
        health.plugEvents = 12
        health.connections = 6
        health.errors = 2
        health.lastOvercurrentAt = snapshot.capturedAt
        return WidgetPayload(snapshot: snapshot, recentPower: samples(600, step: 1),
                             dayPower: samples(288, step: WidgetPayload.dayPowerStep), events: events,
                             portHealth: Dictionary(uniqueKeysWithValues: snapshot.ports.map { ($0.key, health) }),
                             portDays: Dictionary(uniqueKeysWithValues: snapshot.ports.map {
                                 ($0.key, Array(repeating: health, count: 7))
                             }))
    }

    @Test(arguments: DemoScenario.allCases)
    func roundTrips(_ scenario: DemoScenario) throws {
        let payload = Self.fullPayload(scenario)
        let decoded = try JSONDecoder().decode(WidgetPayload.self, from: JSONEncoder().encode(payload))
        #expect(decoded == payload)
        #expect(decoded.schemaVersion == WidgetPayload.currentSchemaVersion)
        #expect(decoded.isDemo)
        #expect(decoded.capturedAt == S.date)
        #expect(decoded.events.count == WidgetPayload.eventLimit)
    }

    @Test(arguments: DemoScenario.allCases)
    func holdsNoSerialNumbersOrPropertyBags(_ scenario: DemoScenario) throws {
        let snapshot = S.snapshot(scenario)
        let payload = Self.fullPayload(scenario)
        let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        let serials = snapshot.allDevices.compactMap(\.device.serialNumber).filter { $0.count >= 4 }
            + DemoScenarioExportTests.serials
        for serial in serials {
            #expect(!json.contains(serial), "\(serial)")
        }
        #expect(snapshot.ports.contains { $0.properties != nil })
        #expect(payload.snapshot.allDevices.allSatisfy { $0.device.properties == nil })
        #expect(payload.snapshot.ports.allSatisfy { $0.properties == nil })
        #expect(!json.contains("\"properties\""))
    }

    @Test(arguments: DemoScenario.allCases)
    func staysUnderTheSizeLimit(_ scenario: DemoScenario) throws {
        let size = try JSONEncoder().encode(Self.fullPayload(scenario)).count
        print("Widget payload, \(scenario.rawValue): \(size) bytes")
        #expect(size < Self.sizeLimit)
    }

    @Test func fileRoundTripsOwnerOnlyAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BusStopWidgetPayloadTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = WidgetPayloadFile(url: directory.appending(path: WidgetPayloadFile.fileName))
        #expect(file.read() == nil)

        let payload = WidgetPayload(snapshot: S.snapshot(.travel))
        try file.write(payload)
        #expect(file.read() == payload)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        var newer = payload
        newer.schemaVersion = WidgetPayload.currentSchemaVersion + 1
        try JSONEncoder().encode(newer).write(to: file.url)
        #expect(file.read() == nil)

        file.delete()
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test func noTeamMeansNoAppGroup() {
        // The test runner's bundle has no BusStopTeamID, like an ad hoc build.
        #expect(WidgetPayloadFile.appGroupID() == nil)
        #expect(WidgetPayloadFile.appGroup() == nil)
    }
}

@Suite("Widget timeline")
struct WidgetTimelineTests {
    private let captured = DemoTestSupport.date

    private func payload(isDemo: Bool) -> WidgetPayload {
        var snapshot = DemoTestSupport.snapshot(.studioDesk)
        snapshot.isDemo = isDemo
        return WidgetPayload(snapshot: snapshot)
    }

    @Test func noPayloadIsEmpty() {
        let entries = WidgetTimeline.entries(payload: nil, now: captured)
        #expect(entries.map(\.state) == [.empty])
        #expect(entries.map(\.date) == [captured])
    }

    @Test(arguments: [(false, WidgetTimeline.State.live), (true, .demo)])
    func freshDataGoesStaleFiveMinutesAfterTheCapture(_ isDemo: Bool, _ state: WidgetTimeline.State) {
        let now = captured + 90
        let entries = WidgetTimeline.entries(payload: payload(isDemo: isDemo), now: now)
        #expect(entries.map(\.state) == [state, .stale])
        #expect(entries.map(\.date) == [now, captured + 5 * 60])
        #expect(entries.allSatisfy { $0.payload != nil })
    }

    @Test func oldDataIsStaleAtOnce() {
        for age in [5 * 60.0, 3_600] {
            let entries = WidgetTimeline.entries(payload: payload(isDemo: false), now: captured + age)
            #expect(entries.map(\.state) == [.stale])
            #expect(entries.first?.payload != nil)
        }
    }
}
