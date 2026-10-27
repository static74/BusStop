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

    /// Only serials that an event's text holds are kept, and they go with the last such event.
    @Test func serialsAreKeptWithTheEventsThatNameThem() throws {
        var archive = HistoryArchive()
        let named = ConnectionEvent(id: "a", date: start, kind: .deviceDisconnected,
                                    title: "Drive SNXYZ123 disconnected", detail: "")
        archive.append([named], model: model, serials: ["SNXYZ123", "OTHER999", "2160"])
        #expect(archive.serials(model: model) == ["SNXYZ123"])
        let decoded = try HistoryArchive.decode(archive.encoded())
        #expect(decoded.serials(model: model) == ["SNXYZ123"])

        archive.trim(now: start.addingTimeInterval(HistoryArchive.eventAge + 1))
        #expect(archive.events(model: model).isEmpty)
        #expect(archive.serials(model: model).isEmpty)

        archive.append([named], model: model, serials: ["SNXYZ123"])
        archive.clearEvents(model: model)
        #expect(archive.serials(model: model).isEmpty)
    }

    /// `count` events, oldest first; those at `named` name a drive by its serial.
    private func events(_ count: Int, naming named: Set<Int>) -> [ConnectionEvent] {
        (0..<count).map { index in
            named.contains(index)
                ? ConnectionEvent(id: "e\(index)", date: start.addingTimeInterval(Double(index)),
                                  kind: .deviceDisconnected, title: "Drive SNXYZ123 disconnected", detail: "")
                : event("e\(index)", Double(index))
        }
    }

    @Test func serialsGoWithEventsDroppedAtTheCountCap() {
        var archive = HistoryArchive()
        archive.append(events(HistoryArchive.maxEvents, naming: [0, 200]), model: model, serials: ["SNXYZ123"])
        // 100 more drop the 100 oldest, e0 among them; e200, which names the drive too, stays.
        for index in 0..<100 { archive.append([event("n\(index)", 1e6 + Double(index))], model: model) }
        #expect(archive.serials(model: model) == ["SNXYZ123"])
        // 101 more drop it.
        for index in 100..<201 { archive.append([event("n\(index)", 1e6 + Double(index))], model: model) }
        #expect(!archive.events(model: model).contains { $0.title.contains("SNXYZ123") })
        #expect(archive.serials(model: model).isEmpty)
    }

    @Test func serialsGoWithEventsDroppedForTheByteCap() throws {
        var archive = HistoryArchive()
        archive.append(events(2_000, naming: [0]), model: model, serials: ["SNXYZ123"])
        let full = try archive.encoded(maxBytes: .max)
        #expect(String(decoding: full, as: UTF8.self).contains("SNXYZ123"))
        let shrunk = try archive.encoded(maxBytes: full.count / 4)
        #expect(!String(decoding: shrunk, as: UTF8.self).contains("SNXYZ123"))

        var newest = HistoryArchive()
        newest.append(events(2_000, naming: [1_999]), model: model, serials: ["SNXYZ123"])
        let kept = try newest.encoded(maxBytes: try newest.encoded(maxBytes: .max).count / 4)
        #expect(try HistoryArchive.decode(kept).serials(model: model) == ["SNXYZ123"])
    }

    /// A bad entry drops only itself, and a serial that only a dropped event held goes with it.
    @Test func serialsDecodeEntryByEntry() throws {
        let json = #"""
        {"schemaVersion":1,"sections":{"Mac17,9":{"serials":["SNXYZ123",5,"GONE1234"],
        "events":[{"id":"a","date":800000000,"kind":"deviceDisconnected","title":"Drive SNXYZ123 disconnected",
        "detail":"","isDowngrade":false},{"id":"b","date":800000001,"kind":"fromANewerVersion",
        "title":"Drive GONE1234 did something new","detail":"","isDowngrade":false}]}}}
        """#
        let archive = try HistoryArchive.decode(Data(json.utf8))
        #expect(archive.events(model: model).count == 1)
        #expect(archive.serials(model: model) == ["SNXYZ123"])
        // A list of the wrong type drops only the list.
        for wrong in [#""SNXYZ123""#, #"{"SNXYZ123":1}"#] {
            let other = json.replacingOccurrences(of: #"["SNXYZ123",5,"GONE1234"]"#, with: wrong)
            let decoded = try HistoryArchive.decode(Data(other.utf8))
            #expect(decoded.events(model: model).count == 1 && decoded.serials(model: model).isEmpty)
        }
    }

    /// Kept only when it is a whole word of an event, as redaction matches it.
    @Test func serialsInsideAWordAreNotKept() {
        var archive = HistoryArchive()
        archive.append([ConnectionEvent(id: "a", date: start, kind: .deviceDisconnected,
                                        title: "DataTraveler 3.0 disconnected", detail: "")],
                       model: model, serials: ["Data"])
        #expect(archive.serials(model: model).isEmpty)
    }

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

        archive.trim(now: start.addingTimeInterval(HistoryArchive.powerAge + 30))
        #expect(archive.sections[model]?.power.map(\.systemInputMilliwatts) == [2])

        // After a step forward of more than a day, ages are trimmed against the capture before the step
        // until the clock has held for a day.
        let later = 2 * HistoryArchive.powerAge
        archive.record(capture(later, inputMilliwatts: 4), afterGap: true)
        #expect(archive.sections[model]?.power.map(\.systemInputMilliwatts) == [2, 3])
        archive.record(capture(later + HistoryArchive.clockTrust, inputMilliwatts: 5), afterGap: false)
        #expect(archive.sections[model]?.power.map(\.systemInputMilliwatts) == [4])
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

    @Test func clockGoingBackwardsDropsThePowerAfterIt() {
        var archive = HistoryArchive()
        archive.append([event("a", 0)], model: model)
        archive.record(capture(0, plugs: 1, inputMilliwatts: 10), afterGap: true)
        archive.record(capture(70, plugs: 2, inputMilliwatts: 20), afterGap: false)
        // The clock goes back two minutes.
        archive.record(capture(-50, plugs: 4, inputMilliwatts: 99), afterGap: false)

        let section = archive.sections[model]
        #expect(archive.events(model: model).count == 1)
        // Both earlier minutes are now in the future, so power starts over from this sample.
        #expect(section?.power.isEmpty == true)
        #expect(section?.pendingPower.map(\.systemInputMilliwatts) == [99])
        // Nothing counted across the step, but the new value is the baseline.
        #expect(days(archive).first?.plugEvents == 1)
        #expect(section?.lastCounters["2/1"]?.plugEventCount == 4)
        #expect(section?.lastCaptureAt == start.addingTimeInterval(-50))

        // Once the clock moves on, deltas count again.
        archive.record(capture(-40, plugs: 5), afterGap: false)
        #expect(days(archive).first?.plugEvents == 2)
    }

    @Test func clockSetAheadThenPutRightKeepsTheHistory() {
        let year = 365 * 86_400.0
        var archive = HistoryArchive()
        archive.append([event("a", 0)], model: model)
        archive.append([event("b", 0)], model: "Mac16,1")
        archive.record(capture(0, plugs: 1, inputMilliwatts: 10), afterGap: true)
        archive.record(capture(70, plugs: 2, inputMilliwatts: 20), afterGap: false)
        // The clock is a year ahead for two captures and a save.
        archive.record(capture(year, plugs: 3, inputMilliwatts: 98), afterGap: false)
        archive.record(capture(year + 10, plugs: 3, inputMilliwatts: 99), afterGap: false)
        archive.trim(now: start.addingTimeInterval(year + 20))
        #expect(archive.events(model: model).count == 1)
        // Another Mac model's section never saw the step, and is kept too.
        #expect(archive.events(model: "Mac16,1").count == 1)
        #expect(archive.sections[model]?.power.map(\.systemInputMilliwatts) == [10, 20])
        #expect(days(archive).map(\.plugEvents) == [1, 1])

        // Put right: the samples and the port day from the future go, and new ones record again.
        archive.record(capture(130, plugs: 4, inputMilliwatts: 30), afterGap: false)
        archive.record(capture(200, plugs: 5, inputMilliwatts: 40), afterGap: false)
        let section = archive.sections[model]
        #expect(archive.events(model: model).count == 1)
        #expect(section?.power.map(\.systemInputMilliwatts) == [10, 20, 30])
        #expect(section?.pendingPower.map(\.systemInputMilliwatts) == [40])
        #expect(days(archive).map(\.plugEvents) == [2])
    }

    @Test func ageTrimsStillRunWhenEverySessionFollowsAGap() {
        var archive = HistoryArchive()
        archive.append([event("old", 0)], model: model)
        // A weekend Mac: four hours of use every three days, for six weeks.
        for session in 0..<14 {
            let t = Double(session) * 3 * 86_400
            archive.record(capture(t, inputMilliwatts: 1), afterGap: true)
            archive.record(capture(t + 4 * 3_600, inputMilliwatts: 1), afterGap: false)
        }
        #expect(archive.events(model: model).isEmpty)
    }

    @Test func counterGoingDownKeepsItsBaseline() {
        var archive = HistoryArchive()
        archive.record(capture(0, plugs: 10, connections: 5, overcurrents: 3), afterGap: true)
        // One low reading, then the real values again: nothing happened.
        archive.record(capture(10, plugs: 2, connections: 1, overcurrents: 0), afterGap: false)
        archive.record(capture(20, plugs: 10, connections: 5, overcurrents: 3), afterGap: false)
        #expect(days(archive).isEmpty)
        #expect(archive.sections[model]?.lastOvercurrentAt.isEmpty == true)
        archive.record(capture(30, plugs: 12, connections: 6, overcurrents: 3), afterGap: false)
        #expect(days(archive).first?.plugEvents == 2)
        #expect(days(archive).first?.connections == 1)
    }

    @Test func aMissingReadingDropsTheBaseline() {
        var archive = HistoryArchive()
        archive.record(capture(0, plugs: 10), afterGap: true)
        // The first capture after wake has no counters, so the next one must not count across the sleep.
        archive.record(capture(3_600), afterGap: true)
        archive.record(capture(3_610, plugs: 13), afterGap: false)
        #expect(days(archive).isEmpty)
        archive.record(capture(3_620, plugs: 14), afterGap: false)
        #expect(days(archive).first?.plugEvents == 1)
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

    @Test func powerSamplesResampleToTheStep() {
        var archive = HistoryArchive()
        var section = HistoryArchive.Section()
        // Minutes 0-19 and 40-41; Bus Stop was not running in between.
        section.power = (Array(0..<20) + [40, 41]).map { minute in
            HistoryArchive.PowerBucket(start: start.addingTimeInterval(Double(minute) * 60),
                                       systemInputMilliwatts: minute * 1_000,
                                       portMilliwatts: minute.isMultiple(of: 2) ? ["2/1": minute * 100] : [:])
        }
        archive.sections[model] = section

        let minutes = archive.powerSamples(model: model, since: start.addingTimeInterval(5 * 60), step: 60)
        #expect(minutes.count == 17)
        #expect(minutes.first?.date == start.addingTimeInterval(5 * 60))
        #expect(minutes.first?.systemInputMilliwatts == 5_000)

        let tens = archive.powerSamples(model: model, since: start, step: 600)
        // Windows with no saved minute are left out, so the gap stays a gap.
        #expect(tens.map(\.date) == [0, 600, 2_400].map { start.addingTimeInterval($0) })
        #expect(tens.map(\.systemInputMilliwatts) == [4_500, 14_500, 40_500])
        // A port is averaged over the minutes that had a reading: 0, 2, 4, 6 and 8.
        #expect(tens.first?.portMilliwatts == ["2/1": 400])
        #expect(archive.powerSamples(model: "Mac16,11", since: start, step: 600).isEmpty)
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
