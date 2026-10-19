import Foundation
import Testing
@testable import BusStopCore

@Suite("Port health")
struct PortHealthTests {
    typealias F = SupportFixtures

    private let start = F.date
    private let model = "Mac17,9"
    private let key1 = PortKey(type: PortKey.usbCType, number: 1)
    private let key2 = PortKey(type: PortKey.usbCType, number: 2)
    private let key3 = PortKey(type: PortKey.usbCType, number: 3)
    /// A fixed zone, so local days do not depend on the machine running the tests.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }()

    /// Three USB-C ports, port 1 with `statistics`, `seconds` after `start`.
    private func capture(_ seconds: TimeInterval, plugs: Int? = nil, connections: Int? = nil,
                         overcurrents: Int? = nil) -> HostSnapshot {
        let stats = PortStatistics(connectionCount: connections, plugEventCount: plugs, overcurrentCount: overcurrents)
        return F.snapshot(ports: [F.usbC(1, "Left Rear", statistics: stats), F.usbC(2, "Left Front"),
                                  F.usbC(3, "Right Rear")],
                          at: start.addingTimeInterval(seconds))
    }

    private func event(_ kind: ConnectionEvent.Kind, _ subject: String, _ seconds: TimeInterval, port: PortKey,
                       device: String? = nil, downgrade: Bool = false) -> ConnectionEvent {
        let date = start.addingTimeInterval(seconds)
        return ConnectionEvent(id: "\(kind.rawValue):\(subject):\(seconds)", date: date, kind: kind, title: subject,
                               detail: "", portKey: port, deviceID: device ?? subject, isDowngrade: downgrade,
                               subjectID: subject)
    }

    /// A device on `port` that leaves `after` seconds after it arrives, at `seconds`.
    private func visit(_ subject: String, _ seconds: TimeInterval, after: TimeInterval, port: PortKey) -> [ConnectionEvent] {
        [event(.deviceConnected, subject, seconds, port: port), event(.deviceDisconnected, subject, seconds + after, port: port)]
    }

    private func health(_ connections: Int, _ errors: Int) -> PortHealth {
        var health = PortHealth()
        health.connections = connections
        health.errors = errors
        return health
    }

    private func standsOut(_ ports: [PortKey: PortHealth], in snapshot: HostSnapshot? = nil) -> [String] {
        DiagnosticsEngine.evaluate(snapshot ?? capture(0), raw: nil, ports: ports)
            .filter { $0.kind == .portStandsOut }.map(\.id)
    }

    // MARK: Counting

    @Test func countsDeltasBetweenTwoAnkerCaptures() throws {
        let first = try AnkerPrimeDockTests.raw()
        var second = first
        second.capturedAt = first.capturedAt.addingTimeInterval(60)
        let index = try #require(second.portNodes.firstIndex { $0.properties.int("Plug Event Count") == 13 })
        second.portNodes[index].properties["Plug Event Count"] = .int(17)
        second.portNodes[index].properties["ConnectionCount"] = .int(9)
        second.portNodes[index].properties["Overcurrent Count"] = .int(1)

        let before = TopologyBuilder.build(first, options: BuildOptions())
        let after = TopologyBuilder.build(second, options: BuildOptions())
        let key = try #require(before.ports.first { $0.statistics?.plugEventCount == 13 }?.key)
        var archive = HistoryArchive()
        archive.record(before, afterGap: true, calendar: calendar)
        archive.record(after, afterGap: false, calendar: calendar)

        let ports = archive.portHealth(model: first.machine.model, now: after.capturedAt, calendar: calendar)
        let port = try #require(ports[key])
        #expect(port.plugEvents == 4)
        #expect(port.connections == 2)
        #expect(port.overcurrents == 1)
        #expect(port.lastOvercurrentAt == after.capturedAt)
        // The dock's other port did not move.
        #expect(ports.count == 1)
    }

    @Test func decreasingCounterStartsANewEpoch() {
        var archive = HistoryArchive()
        archive.record(capture(0, plugs: 10), afterGap: true, calendar: calendar)
        archive.record(capture(10, plugs: 12), afterGap: false, calendar: calendar)
        archive.record(capture(20, plugs: 2), afterGap: false, calendar: calendar)
        archive.record(capture(30, plugs: 5), afterGap: false, calendar: calendar)
        #expect(archive.portHealth(model: model, now: start.addingTimeInterval(30), calendar: calendar)[key1]?
            .plugEvents == 5)
    }

    @Test func lastWeekFollowsLocalDays() throws {
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 12)))
        let firstDay = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        var archive = HistoryArchive()
        for (offset, plugs) in [(-7_200.0, 0), (-1_800, 1), (1_800, 3)] {
            var snapshot = capture(0, plugs: plugs)
            snapshot.capturedAt = firstDay.addingTimeInterval(offset)
            archive.record(snapshot, afterGap: plugs == 0, calendar: calendar)
        }
        // One plug at 23:30 the day before the window, two at 00:30 on its first day.
        let ports = archive.portHealth(model: model, now: now, calendar: calendar)
        #expect(ports[key1]?.plugEvents == 2)
    }

    @Test func shortConnectionsDowngradesAndFallbacksAreErrors() {
        var archive = HistoryArchive()
        var events = visit("usb:phone", 0, after: 5, port: key1)          // short: an error
            + visit("usb:drive", 20, after: 30, port: key1)               // long enough
        events.append(event(.linkChanged, "usb:t9", 60, port: key1, downgrade: true))
        // The fallback this slowdown raised at the same moment counts once with it.
        events.append(event(.diagnosticRaised, "usb2Fallback:usb:t9", 60, port: key1, device: "usb:t9"))
        events.append(event(.diagnosticRaised, "usb2Fallback:usb:stick", 70, port: key2, device: "usb:stick"))
        events.append(event(.linkChanged, "usb:t9", 80, port: key1))      // faster: fine
        events.append(event(.diagnosticRaised, "hubOverBudget:usb:hub", 90, port: key1))
        // Moved to port 2 without events, then left: not port 1's error.
        events.append(event(.deviceConnected, "usb:cam", 100, port: key1))
        events.append(event(.deviceDisconnected, "usb:cam", 105, port: key2))
        // Two parts of one dock slow down together: two errors, each part's fallback counted with its slowdown.
        events.append(event(.linkChanged, "usb:dock-a", 120, port: key2, device: "usb:dock", downgrade: true))
        events.append(event(.linkChanged, "usb:dock-b", 120, port: key2, device: "usb:dock", downgrade: true))
        events.append(event(.diagnosticRaised, "usb2Fallback:usb:dock-a", 120, port: key2, device: "usb:dock"))
        // The same stick falling back again on later plug-ins is the same cable, not new errors.
        events.append(event(.diagnosticRaised, "usb2Fallback:usb:stick", 130, port: key2, device: "usb:stick"))
        events.append(event(.diagnosticRaised, "usb2Fallback:usb:stick", 140, port: key2, device: "usb:stick"))
        // A display that retrains to a slower DisplayPort rate is not a connection error.
        events.append(event(.linkChanged, "display:10ac:a0c4:1", 150, port: key2, downgrade: true))
        // Eight days ago: outside the window.
        events += visit("usb:old", -8 * 86_400, after: 1, port: key1)
        // Connected 3 seconds before the window starts, left 2 seconds into it: an error inside the window.
        let windowStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: start))!
        events += visit("usb:edge", windowStart.timeIntervalSince(start) - 3, after: 5, port: key1)
        archive.append(events.sorted { $0.date < $1.date }, model: model)
        // The clock was set back a minute while the reader was plugged in: logged in this order, not a short connection.
        archive.append([event(.deviceConnected, "usb:reader", 170, port: key1),
                        event(.deviceDisconnected, "usb:reader", 110, port: key1)], model: model)

        let ports = archive.portHealth(model: model, now: start.addingTimeInterval(200), calendar: calendar)
        #expect(ports[key1]?.errors == 3)
        #expect(ports[key2]?.errors == 3)
    }

    // MARK: Stands out

    @Test func portStandsOutAgainstItsSiblingsMedian() throws {
        // Siblings at 0.1 and 0 errors per connection: the median floor of 0.05 applies.
        #expect(standsOut([key1: health(10, 5), key2: health(10, 1), key3: health(10, 0)]) == ["portStandsOut:2/1"])
        let finding = try #require(DiagnosticsEngine.evaluate(capture(0), raw: nil,
                                                              ports: [key1: health(10, 5), key2: health(10, 0),
                                                                      key3: health(10, 0)]).first)
        #expect(finding.severity == .info)
        #expect(finding.portKey == key1)
        #expect(finding.detail.contains("5 connection problems over 10 connections"))
        // Siblings at 0.2 put the bar at 0.6.
        #expect(standsOut([key1: health(10, 5), key2: health(10, 2), key3: health(10, 2)]).isEmpty)
    }

    @Test func standsOutUsesSevenDaysForBothCounts() {
        var archive = HistoryArchive()
        var section = HistoryArchive.Section()
        var old = HistoryArchive.PortDay(day: calendar.startOfDay(for: start.addingTimeInterval(-9 * 86_400)))
        old.connections = 40
        var recent = HistoryArchive.PortDay(day: calendar.startOfDay(for: start))
        recent.connections = 5
        section.portDays["2/1"] = [old, recent]
        section.portDays["2/2"] = [recent]
        section.portDays["2/3"] = [recent]
        archive.sections[model] = section
        // Three short connections on port 1 this week; port 2's were nine days ago.
        let events = visit("usb:a", 0, after: 1, port: key1) + visit("usb:b", 10, after: 1, port: key1)
            + visit("usb:c", 20, after: 1, port: key1)
            + (0..<5).flatMap { visit("usb:old\($0)", -9 * 86_400 + Double($0) * 10, after: 1, port: key2) }
        archive.append(events.sorted { $0.date < $1.date }, model: model)

        let ports = archive.portHealth(model: model, now: start.addingTimeInterval(100), calendar: calendar)
        #expect(ports[key1]?.connections == 5)
        #expect(ports[key2]?.errors == 0)
        // 3 of 5, not 3 of 45.
        #expect(standsOut(ports) == ["portStandsOut:2/1"])
    }

    @Test func fewConnectionsNeverStandOut() {
        let siblings = [key2: health(5, 0), key3: health(5, 0)]
        #expect(standsOut(siblings.merging([key1: health(4, 4)]) { $1 }).isEmpty)
        #expect(standsOut(siblings.merging([key1: health(5, 2)]) { $1 }).isEmpty)
        #expect(standsOut(siblings.merging([key1: health(5, 3)]) { $1 }) == ["portStandsOut:2/1"])
    }

    @Test func unusedSiblingsAreNotCompared() {
        // The other two ports were barely used: nothing to compare port 1 with.
        #expect(standsOut([key1: health(5, 3)]).isEmpty)
        #expect(standsOut([key1: health(5, 3), key2: health(5, 0), key3: health(4, 0)]).isEmpty)
    }

    @Test func differentPortKindsAreNotCompared() {
        let bad = [key1: health(10, 9)]
        // Only one other USB-C port.
        let twoPorts = F.snapshot(ports: [F.usbC(1, "Left Rear"), F.usbC(2, "Left Front")])
        #expect(standsOut(bad, in: twoPorts).isEmpty)
        // MagSafe and HDMI are not siblings of a USB-C port.
        let mixed = F.snapshot(ports: [F.usbC(1, "Left Rear"), F.magSafe(), F.hdmi()])
        #expect(standsOut(bad, in: mixed).isEmpty)
    }

    // MARK: Overcurrent

    @Test func overcurrentWarningSurvivesARelaunch() throws {
        var archive = HistoryArchive()
        archive.record(capture(0, overcurrents: 2), afterGap: true, calendar: calendar)
        archive.record(capture(10, overcurrents: 3), afterGap: false, calendar: calendar)
        var relaunched = try HistoryArchive.decode(archive.encoded())
        // The first capture after launch counts nothing but keeps the last overcurrent.
        let later = capture(3_600, overcurrents: 3)
        relaunched.record(later, afterGap: true, calendar: calendar)

        let ports = relaunched.portHealth(model: model, now: later.capturedAt, calendar: calendar)
        let findings = DiagnosticsEngine.evaluate(later, raw: nil, ports: ports)
        #expect(findings.map(\.id) == ["overcurrent:2/1"])
        #expect(findings.first?.detail.contains("once, in the last 24 hours") == true)
    }

    @Test func overcurrentWarningEndsAfterTwentyFourHours() {
        var archive = HistoryArchive()
        archive.record(capture(0, overcurrents: 0), afterGap: true, calendar: calendar)
        archive.record(capture(10, overcurrents: 1), afterGap: false, calendar: calendar)
        func kinds(hours: Double) -> [DiagnosticKind] {
            let snapshot = capture(10 + hours * 3_600, overcurrents: 1)
            let ports = archive.portHealth(model: model, now: snapshot.capturedAt, calendar: calendar)
            return DiagnosticsEngine.evaluate(snapshot, raw: nil, ports: ports).map(\.kind)
        }
        #expect(kinds(hours: 23) == [.overcurrent])
        #expect(kinds(hours: 25).isEmpty)
    }

    @Test func overcurrentIsNotAnError() {
        var archive = HistoryArchive()
        archive.record(capture(0, connections: 0, overcurrents: 0), afterGap: true, calendar: calendar)
        archive.record(capture(10, connections: 6, overcurrents: 6), afterGap: false, calendar: calendar)
        let snapshot = capture(20, connections: 6, overcurrents: 6)
        let ports = archive.portHealth(model: model, now: snapshot.capturedAt, calendar: calendar)
        #expect(ports[key1]?.overcurrents == 6)
        #expect(ports[key1]?.errors == 0)
        #expect(DiagnosticsEngine.evaluate(snapshot, raw: nil, ports: ports).map(\.kind) == [.overcurrent])
    }
}
