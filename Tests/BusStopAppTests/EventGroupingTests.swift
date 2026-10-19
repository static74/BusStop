import BusStopCore
import Foundation
import Testing
@testable import BusStopApp

/// The Events page groups the saved log (up to 5,000 events) by day.
@MainActor
@Suite("Event grouping")
struct EventGroupingTests {
    private let start = Date(timeIntervalSince1970: 1_791_115_200)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// `count` events, one every `spacing` seconds before `start`, newest first.
    private func log(_ count: Int, spacing: TimeInterval = 600) -> [ConnectionEvent] {
        // Split into typed lets: the Xcode 26.6 compiler times out type-checking the one-expression form.
        (0..<count).map { (i: Int) -> ConnectionEvent in
            let date = start.addingTimeInterval(-Double(i) * spacing)
            let kind: ConnectionEvent.Kind = i % 3 == 0 ? .deviceDisconnected : .deviceConnected
            let title = i % 2 == 0 ? "Samsung T9" : "Keyboard"
            return ConnectionEvent(id: "e\(i)", date: date, kind: kind, title: title, detail: "Left Front")
        }
    }

    @Test func groupsFiveThousandEventsByDayNewestFirst() {
        let events = log(HistoryArchive.maxEvents)
        let groups = EventDayGroup.groups(events, filter: .all, query: "", calendar: utc)

        // 600 s apart: 144 a day over about 34.7 days.
        #expect(groups.count == Set(events.map { utc.startOfDay(for: $0.date) }).count)
        #expect(groups.count >= 35)
        #expect(groups.map(\.day) == groups.map(\.day).sorted(by: >))
        #expect(groups.reduce(0) { $0 + $1.events.count } == events.count)
        #expect(groups.first?.events.first?.id == "e0")
        for group in groups {
            #expect(group.events.allSatisfy { utc.startOfDay(for: $0.date) == group.day })
            #expect(group.events.map(\.date) == group.events.map(\.date).sorted(by: >))
        }
    }

    @Test func filterAndSearchApplyBeforeGrouping() {
        let events = log(300)
        let disconnects = EventDayGroup.groups(events, filter: .kind(.deviceDisconnected), query: "", calendar: utc)
        #expect(disconnects.flatMap(\.events).count == 100)
        #expect(disconnects.flatMap(\.events).allSatisfy { $0.kind == .deviceDisconnected })

        let keyboards = EventDayGroup.groups(events, filter: .all, query: "keyboard", calendar: utc)
        #expect(keyboards.flatMap(\.events).count == 150)
        #expect(EventDayGroup.groups(events, filter: .all, query: "nothing like it", calendar: utc).isEmpty)
    }

    @Test func problemsFilterKeepsWarningsAndDowngrades() {
        func event(_ id: String, _ kind: ConnectionEvent.Kind, downgrade: Bool = false,
                   severity: DiagnosticSeverity? = nil) -> ConnectionEvent {
            ConnectionEvent(id: id, date: start, kind: kind, title: id, detail: "", isDowngrade: downgrade,
                            severity: severity)
        }
        let events = [
            event("flaky", .diagnosticRaised, severity: .warning),
            event("liquid", .diagnosticRaised, severity: .critical),
            event("saved before severities", .diagnosticRaised),
            event("bottleneck", .diagnosticRaised, severity: .info),
            event("slower", .linkChanged, downgrade: true),
            event("faster", .linkChanged),
            event("plugged", .deviceConnected),
        ]
        let kept = EventDayGroup.groups(events, filter: .problems, query: "", calendar: utc).flatMap(\.events)
        #expect(Set(kept.map(\.id)) == ["flaky", "liquid", "saved before severities", "slower"])
    }

    @Test func cacheRegroupsOnlyWhenSomethingChanged() {
        let cache = EventGroupCache()
        let events = log(10)
        let first = cache.groups(events, filter: .all, query: "")
        #expect(first.flatMap(\.events).count == 10)
        #expect(cache.groups(Array(events.dropLast()), filter: .all, query: "").flatMap(\.events).count == 9)
        #expect(cache.groups(events, filter: .all, query: "keyboard").flatMap(\.events).count == 5)
    }
}
