import Foundation
import Testing
@testable import BusStopCore

@Suite("History archive")
struct HistoryArchiveTests {
    typealias F = SupportFixtures

    private let start = SupportFixtures.date
    private let model = "Mac17,9"

    /// A one-port capture `seconds` after `start`.
    private func capture(_ seconds: TimeInterval, model: String? = nil, plugs: Int? = nil, connections: Int? = nil,
                         overcurrents: Int? = nil, liquid: Bool = false, inputMilliwatts: Int? = nil,
                         portMilliwatts: Int? = nil) -> HostSnapshot {
        let stats = (plugs ?? connections ?? overcurrents) == nil ? nil
            : PortStatistics(connectionCount: connections, plugEventCount: plugs, overcurrentCount: overcurrents)
        let power = portMilliwatts.map { PortPower(direction: .output, milliwatts: $0, source: .telemetry) }
        return F.snapshot(machine: F.laptop(model: model ?? self.model),
                          ports: [F.usbC(1, "Left Rear", power: power, statistics: stats, liquid: liquid)],
                          power: PowerSummary(systemInputMilliwatts: inputMilliwatts, systemLoadMilliwatts: 9_000,
                                              hasBattery: true),
                          at: start.addingTimeInterval(seconds))
    }

    private func event(_ id: String, _ seconds: TimeInterval, kind: ConnectionEvent.Kind = .deviceConnected) -> ConnectionEvent {
        ConnectionEvent(id: id, date: start.addingTimeInterval(seconds), kind: kind, title: id, detail: "")
    }

    private func days(_ archive: HistoryArchive, _ model: String? = nil) -> [HistoryArchive.PortDay] {
        archive.sections[model ?? self.model]?.portDays["2/1"] ?? []
    }

    // MARK: Codec

    @Test func roundTripKeepsEventsPowerAndCounters() throws {
        var archive = HistoryArchive()
        archive.record(capture(0, plugs: 1, inputMilliwatts: 60_000), afterGap: true)
        archive.record(capture(30, plugs: 3, inputMilliwatts: 62_000), afterGap: false)
        archive.record(capture(70, plugs: 3, inputMilliwatts: 61_000), afterGap: false)
        archive.append([event("a", 10), event("b", 20)], model: model)

        let decoded = try HistoryArchive.decode(archive.encoded())
        #expect(decoded == archive)
        #expect(decoded.events(model: model).map(\.id) == ["b", "a"])
        #expect(decoded.sections[model]?.power.count == 1)
        #expect(days(decoded).first?.plugEvents == 2)
    }

    @Test func datesSurviveToTheMillisecond() throws {
        var archive = HistoryArchive()
        let id = "deviceConnected:usb:t9:\(Int64(start.addingTimeInterval(1.234).timeIntervalSince1970 * 1000))"
        archive.append([event(id, 1.234)], model: model)
        archive.record(capture(61.567), afterGap: true)

        let decoded = try HistoryArchive.decode(archive.encoded())
        #expect(decoded.events(model: model).first?.date == start.addingTimeInterval(1.234))
        #expect(decoded.events(model: model).first?.id == id)
        #expect(decoded.sections[model]?.lastCaptureAt == start.addingTimeInterval(61.567))
        #expect(decoded.sections[model]?.pendingPower.first?.date == start.addingTimeInterval(61.567))
    }

    @Test func unknownEventKindDropsOnlyThatEvent() throws {
        var archive = HistoryArchive()
        archive.append([event("a", 1), event("b", 2, kind: .linkChanged), event("c", 3)], model: model)
        let json = try #require(String(data: archive.encoded(), encoding: .utf8))
        let future = Data(json.replacingOccurrences(of: "\"linkChanged\"", with: "\"cableWiggled\"").utf8)

        let decoded = try HistoryArchive.decode(future)
        #expect(decoded.events(model: model).map(\.id) == ["c", "a"])
    }

    @Test func truncatedFileIsCorrupt() throws {
        var archive = HistoryArchive()
        archive.append([event("a", 1)], model: model)
        let data = try archive.encoded()
        #expect(throws: HistoryArchive.DecodeError.corrupt) { try HistoryArchive.decode(data.prefix(data.count / 2)) }
        #expect(throws: HistoryArchive.DecodeError.corrupt) { try HistoryArchive.decode(Data("not json".utf8)) }
    }

    @Test func newerSchemaIsRefused() {
        let data = Data(#"{"schemaVersion": 2, "sections": {"Mac17,9": {"something": "new"}}}"#.utf8)
        #expect(throws: HistoryArchive.DecodeError.newerSchema(2)) { try HistoryArchive.decode(data) }
    }

    @Test func byteCapDropsOldestEntriesFirst() throws {
        var archive = HistoryArchive()
        archive.append((0..<2_000).map { event("event-\($0)", Double($0)) }, model: model)
        let full = try archive.encoded(maxBytes: .max)
        let data = try archive.encoded(maxBytes: full.count / 4)

        #expect(data.count <= full.count / 4)
        let kept = try HistoryArchive.decode(data).events(model: model)
        #expect(kept.count < 2_000 && kept.count > 100)
        #expect(kept.first?.id == "event-1999")
        #expect(kept.map(\.id) == Array(archive.events(model: model).prefix(kept.count)).map(\.id))
    }

    // MARK: Caps

    @Test func eventsCappedByCountAndAge() {
        var archive = HistoryArchive()
        archive.append((0..<(HistoryArchive.maxEvents + 10)).map { event("e\($0)", Double($0)) }, model: model)
        #expect(archive.events(model: model).count == HistoryArchive.maxEvents)
        #expect(archive.events(model: model).first?.id == "e\(HistoryArchive.maxEvents + 9)")

        archive.trim(now: start.addingTimeInterval(HistoryArchive.eventAge + 100))
        #expect(archive.events(model: model).allSatisfy { $0.date >= start.addingTimeInterval(100) })
        #expect(archive.events(model: model).count == HistoryArchive.maxEvents + 10 - 100)
    }

    @Test func powerKeptForSevenDays() {
        var archive = HistoryArchive()
        archive.record(capture(0, inputMilliwatts: 1), afterGap: true)
        archive.record(capture(60, inputMilliwatts: 2), afterGap: false)
        archive.record(capture(120, inputMilliwatts: 3), afterGap: false)
        #expect(archive.sections[model]?.power.count == 2)

        archive.record(capture(HistoryArchive.powerAge + 30, inputMilliwatts: 4), afterGap: true)
        #expect(archive.sections[model]?.power.map(\.systemInputMilliwatts) == [2, 3])
    }

    @Test func portDaysKeptForNinetyDays() {
        var archive = HistoryArchive()
        archive.record(capture(0, plugs: 1), afterGap: true)
        archive.record(capture(10, plugs: 2), afterGap: false)
        #expect(days(archive).count == 1)

        archive.trim(now: start.addingTimeInterval(HistoryArchive.portDayAge - 86_400))
        #expect(days(archive).count == 1)
        archive.trim(now: start.addingTimeInterval(HistoryArchive.portDayAge + 86_400))
        #expect(days(archive).isEmpty)
        #expect(archive.sections[model]?.portDays["2/1"] == nil)
    }

    // MARK: Recording

    @Test func clockGoingBackwardsDropsOnlyOutOfOrderSamples() {
        var archive = HistoryArchive()
        archive.append([event("a", 0)], model: model)
        archive.record(capture(0, plugs: 1, inputMilliwatts: 10), afterGap: true)
        archive.record(capture(70, plugs: 2, inputMilliwatts: 20), afterGap: false)
        // The clock goes back two minutes.
        archive.record(capture(-50, plugs: 4, inputMilliwatts: 99), afterGap: false)

        let section = archive.sections[model]
        #expect(archive.events(model: model).count == 1)
        #expect(section?.power.map(\.systemInputMilliwatts) == [10])
        #expect(section?.pendingPower.map(\.systemInputMilliwatts) == [20])
        // Nothing counted across the step, but the new value is the baseline.
        #expect(days(archive).first?.plugEvents == 1)
        #expect(section?.lastCounters["2/1"]?.plugEventCount == 4)
        #expect(section?.lastCaptureAt == start.addingTimeInterval(-50))

        // Once the clock moves on, deltas count again.
        archive.record(capture(-40, plugs: 5), afterGap: false)
        #expect(days(archive).first?.plugEvents == 2)
    }

    @Test func counterGoingDownStartsANewEpoch() {
        var archive = HistoryArchive()
        archive.record(capture(0, plugs: 10, connections: 5), afterGap: true)
        archive.record(capture(10, plugs: 2, connections: 1), afterGap: false)
        #expect(days(archive).isEmpty)
        archive.record(capture(20, plugs: 4, connections: 2), afterGap: false)
        #expect(days(archive).first?.plugEvents == 2)
        #expect(days(archive).first?.connections == 1)
    }

    @Test func noDeltasAfterAGap() {
        var archive = HistoryArchive()
        archive.record(capture(0, plugs: 1, overcurrents: 0, liquid: false), afterGap: true)
        archive.record(capture(3_600, plugs: 9, overcurrents: 2, liquid: true), afterGap: true)
        #expect(days(archive).isEmpty)
        #expect(archive.sections[model]?.lastOvercurrentAt.isEmpty == true)
    }

    @Test func displaySleepCapturesStillCountDeltas() {
        // While the screens sleep, captures arrive only on hardware changes, minutes apart.
        var archive = HistoryArchive()
        archive.record(capture(0, plugs: 1), afterGap: true)
        archive.record(capture(300, plugs: 3), afterGap: false)
        archive.record(capture(900, plugs: 5), afterGap: false)
        #expect(days(archive).first?.plugEvents == 4)
    }

    @Test func portDaysFollowTheLocalCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        // start is 05:00 in Los Angeles; 18 h 30 m later is 23:30 there, and an hour after that is the next day.
        var archive = HistoryArchive()
        archive.record(capture(66_600, plugs: 1), afterGap: true, calendar: calendar)
        archive.record(capture(66_660, plugs: 2), afterGap: false, calendar: calendar)
        archive.record(capture(70_200, plugs: 4), afterGap: false, calendar: calendar)

        let kept = days(archive)
        #expect(kept.map(\.plugEvents) == [1, 2])
        #expect(kept.first?.day == calendar.startOfDay(for: start))
        #expect(kept.last?.day == calendar.startOfDay(for: start.addingTimeInterval(86_400)))
        // In UTC both captures fall on the same day.
        #expect(Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!,
                from: start.addingTimeInterval(66_660)).day == 5)
    }

    @Test func lastOvercurrentIsRemembered() {
        var archive = HistoryArchive()
        archive.record(capture(0, overcurrents: 1), afterGap: true)
        archive.record(capture(10, overcurrents: 1), afterGap: false)
        #expect(archive.sections[model]?.lastOvercurrentAt["2/1"] == nil)
        archive.record(capture(20, overcurrents: 2), afterGap: false)
        archive.record(capture(30, overcurrents: 2), afterGap: false)
        #expect(archive.sections[model]?.lastOvercurrentAt["2/1"] == start.addingTimeInterval(20))
        #expect(days(archive).first?.overcurrents == 1)
    }

    @Test func minuteBucketsAverageTheirSamples() throws {
        var archive = HistoryArchive()
        archive.record(capture(0, inputMilliwatts: 10_000, portMilliwatts: 4_000), afterGap: true)
        archive.record(capture(20, inputMilliwatts: 20_000), afterGap: false)
        archive.record(capture(40, inputMilliwatts: 30_000, portMilliwatts: 6_000), afterGap: false)
        #expect(archive.sections[model]?.power.isEmpty == true)
        archive.record(capture(60, inputMilliwatts: 1), afterGap: false)

        let bucket = try #require(archive.sections[model]?.power.first)
        #expect(bucket.start == start)
        #expect(bucket.systemInputMilliwatts == 20_000)
        #expect(bucket.systemLoadMilliwatts == 9_000)
        #expect(bucket.batteryMilliwatts == nil)
        // A port is averaged over the samples that had a reading.
        #expect(bucket.portMilliwatts == ["2/1": 5_000])
        #expect(archive.sections[model]?.pendingPower.count == 1)
    }

    @Test func eachModelHasItsOwnSection() {
        var archive = HistoryArchive()
        archive.record(capture(0, plugs: 1), afterGap: true)
        archive.record(capture(10, model: "Mac16,11", plugs: 5), afterGap: true)
        archive.record(capture(20, plugs: 2), afterGap: false)
        archive.append([event("a", 0)], model: model)
        archive.append([event("b", 0)], model: "Mac16,11")

        #expect(days(archive).first?.plugEvents == 1)
        #expect(days(archive, "Mac16,11").isEmpty)
        #expect(archive.events(model: model).map(\.id) == ["a"])
        #expect(archive.events(model: "Mac16,11").map(\.id) == ["b"])
        // Port days are dated by the start of their local day.
        #expect(archive.summary == HistoryArchive.Summary(eventCount: 2, oldest: Calendar.current.startOfDay(for: start)))

        archive.clearEvents(model: model)
        #expect(archive.events(model: model).isEmpty)
        #expect(archive.events(model: "Mac16,11").count == 1)
    }

    @Test func duplicateEventIDsAreSkipped() {
        var archive = HistoryArchive()
        archive.append([event("a", 1), event("b", 2)], model: model)
        archive.append([event("b", 2), event("c", 3), event("c", 3)], model: model)
        #expect(archive.events(model: model).map(\.id) == ["c", "b", "a"])
    }

    @Test func liquidTransitionsAreCounted() {
        var archive = HistoryArchive()
        // Liquid already present at launch is not a new detection.
        archive.record(capture(0, liquid: true), afterGap: true)
        archive.record(capture(10, liquid: true), afterGap: false)
        archive.record(capture(20, liquid: false), afterGap: false)
        archive.record(capture(30, liquid: true), afterGap: false)
        archive.record(capture(40, liquid: true), afterGap: false)
        #expect(days(archive).first?.liquidDetections == 1)
    }
}
