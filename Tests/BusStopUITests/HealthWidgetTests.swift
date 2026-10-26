import AppKit
import BusStopCore
import Foundation
import SwiftUI
import Testing
import WidgetKit
@testable import BusStopUI

@Suite("Health widget")
@MainActor
struct HealthWidgetTests {
    typealias S = WidgetTestSupport

    // MARK: Payloads

    /// A payload like the app writes after watching `scenario` for two
    /// minutes: the findings `ConnectionHealth` raises, the event log, and
    /// port health from an archive fed the same captures. `WidgetTestSupport`
    /// has no port health, and its snapshot no connection-health findings.
    static func livePayload(_ scenario: DemoScenario, keepsHistory: Bool = true) -> WidgetPayload {
        var archive = HistoryArchive()
        var health = ConnectionHealth()
        var previous = S.snapshot(.unplugged)
        var snapshot = previous
        for tick in 0..<60 {
            let date = S.date - Double(59 - tick) * 2
            let raw = scenario.raw(at: date, tick: tick)
            snapshot = TopologyBuilder.build(raw, options: BuildOptions(isDemo: true))
            archive.record(snapshot, afterGap: tick == 0)
            let extra = health.observe(snapshot, afterGap: tick == 0)
            snapshot.diagnostics = DiagnosticsEngine.evaluate(
                snapshot, raw: raw, ports: archive.portHealth(model: snapshot.machine.model, now: date), extra: extra)
            archive.append(SnapshotDiffer.events(from: previous, to: snapshot, at: date), model: snapshot.machine.model)
            previous = snapshot
        }
        let model = snapshot.machine.model
        guard keepsHistory else { return WidgetPayload(snapshot: snapshot) }
        return WidgetPayload(snapshot: snapshot, events: archive.events(model: model),
                             portHealth: archive.portHealth(model: model, now: S.date),
                             portDays: archive.dailyPortHealth(model: model, now: S.date))
    }

    /// `payload` with a made-up week before today, so the strip shows every kind of day.
    static func withWeek(_ payload: WidgetPayload) -> WidgetPayload {
        var payload = payload
        var days = payload.portDays ?? [:]
        for (index, port) in payload.snapshot.ports.filter({ $0.statistics != nil }).enumerated() {
            var week = days[port.key] ?? Array(repeating: PortHealth(), count: 7)
            for day in 0..<6 where (day + index) % 3 != 0 {
                week[day].connections += 2 + index
                week[day].plugEvents += 2 + index
            }
            if index == 1 { week[2].errors += 2 }
            if index == 2 { week[4].overcurrents += 1 }
            days[port.key] = week
            payload.portHealth[port.key] = week.reduce(into: PortHealth()) { total, day in
                total.connections += day.connections
                total.plugEvents += day.plugEvents
                total.errors += day.errors
                total.overcurrents += day.overcurrents
            }
        }
        payload.portDays = days
        return payload
    }

    /// The studio desk with more findings than fit, in `ConnectionHealth`'s and `DiagnosticsEngine`'s words.
    static func crowded() -> WidgetPayload {
        var payload = withWeek(livePayload(.studioDesk))
        let port = payload.snapshot.ports[2].key
        payload.snapshot.diagnostics += [
            Diagnostic(id: "liquid", kind: .liquidDetected, severity: .critical,
                       title: "Liquid detected in Left Front · USB-C",
                       detail: "macOS has detected liquid or debris in this port and may limit power until it is dry.",
                       suggestion: "Unplug the cable and let the port dry before using it again.", portKey: port),
            Diagnostic(id: "hub", kind: .flakyConnection, severity: .warning,
                       title: "Devices behind USB3.1 Hub keep disconnecting",
                       detail: "3 devices behind USB3.1 Hub on Left Front · USB-C disconnected and came back in the "
                           + "last 10 minutes while the hub stayed connected. Likely cause: the hub. It has no power "
                           + "supply of its own, so it may not have enough power for them.",
                       suggestion: "Use a hub with its own power adapter, or move power-hungry devices to another port.",
                       portKey: port),
            Diagnostic(id: "slow", kind: .speedRegression, severity: .warning,
                       title: "PSSD T7 Shield is running slower than before",
                       detail: "PSSD T7 Shield is connected at 5 Gb/s on Left Front · USB-C, but it ran at 10 Gb/s on "
                           + "this port earlier. Likely cause: the cable.", portKey: port),
            Diagnostic(id: "note", kind: .thunderboltBottleneck, severity: .info,
                       title: "The SSD behind the display shares its link", detail: "A note."),
        ]
        return payload
    }

    /// The dock station, which has no findings, with one note.
    static func notesOnly() -> WidgetPayload {
        var payload = withWeek(livePayload(.dockStation))
        payload.snapshot.diagnostics = [
            Diagnostic(id: "note", kind: .portStandsOut, severity: .info,
                       title: "Rear (left) · USB-C has more connection problems than the other ports",
                       detail: "In the last 7 days, Rear (left) · USB-C had 6 connection problems over 9 connections.",
                       suggestion: "Check the port for dust or damage, and try the same cable and device on another "
                           + "port.", portKey: payload.snapshot.ports[2].key),
        ]
        return payload
    }

    static func entry(_ payload: WidgetPayload) -> WidgetTimeline.Entry {
        WidgetTimeline.Entry(date: S.date, state: payload.isDemo ? .demo : .live, payload: payload)
    }

    /// The widget with its links drawn as plain content, which `ImageRenderer` can draw.
    static func view(_ entry: WidgetTimeline.Entry, _ family: WidgetFamily) -> some View {
        HealthWidgetView(entry: entry, family: family).environment(\.healthLinksEnabled, false)
    }

    static let families: [(S.Family, WidgetFamily)] = [(.large, .systemLarge), (.extraLarge, .systemExtraLarge)]

    /// True when the view draws past its frame: SwiftUI does not clip, so
    /// content that does not fit spills into the margin around it.
    static func overflows(_ view: some View, _ family: S.Family) throws -> Bool {
        let margin = 24
        let renderer = ImageRenderer(content: view
            .frame(width: family.size.width, height: family.size.height)
            .padding(CGFloat(margin)))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let inside = x >= margin && x < bitmap.pixelsWide - margin && y >= margin && y < bitmap.pixelsHigh - margin
                if !inside, let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.05 { return true }
            }
        }
        return false
    }

    // MARK: Rendering

    @Test(arguments: DemoScenario.allCases)
    func drawsEveryScenarioWithoutSpilling(_ scenario: DemoScenario) throws {
        for payload in [S.payload(scenario), Self.livePayload(scenario), Self.withWeek(Self.livePayload(scenario))] {
            for (family, widgetFamily) in Self.families {
                let view = Self.view(Self.entry(payload), widgetFamily)
                #expect(S.hasContent(try S.render(view, family)), "\(scenario) \(family)")
                #expect(!(try Self.overflows(view, family)), "\(scenario) \(family)")
            }
        }
    }

    @Test(arguments: DemoScenario.allCases)
    func drawsInVibrantRendering(_ scenario: DemoScenario) throws {
        for (family, widgetFamily) in Self.families {
            let view = Self.view(Self.entry(Self.withWeek(Self.livePayload(scenario))), widgetFamily)
                .environment(\.widgetRenderingMode, .vibrant)
            #expect(S.hasContent(try S.render(view, family)), "\(scenario) \(family)")
            #expect(!(try Self.overflows(view, family)), "\(scenario) \(family)")
        }
    }

    @Test func drawsWithHistoryOffAndEveryState() throws {
        let off = Self.livePayload(.flakyCable, keepsHistory: false)
        for (family, widgetFamily) in Self.families {
            for entry in [Self.entry(off), Self.entry(Self.crowded()), Self.entry(Self.notesOnly()),
                          WidgetTimeline.Entry(date: S.date, state: .stale, payload: off),
                          WidgetTimeline.Entry(date: S.date, state: .empty, payload: nil)] {
                let view = Self.view(entry, widgetFamily)
                #expect(S.hasContent(try S.render(view, family), fraction: 0.001), "\(entry.state) \(family)")
                #expect(!(try Self.overflows(view, family)), "\(entry.state) \(family)")
            }
        }
    }

    // MARK: What is listed

    @Test func flakyCableListsTheFlakyConnectionFirstWithItsCause() throws {
        let model = HealthWidgetModel(Self.livePayload(.flakyCable))
        let first = try #require(model.findings.first)
        #expect(first.kind == .flakyConnection)
        #expect(first.title == "iPhone keeps disconnecting")
        #expect(HealthWidgetModel.likelyCause(first.detail).cause == "Likely cause: the cable")
        #expect(model.findings.map(\.kind) == [.flakyConnection, .usb2Fallback])
        #expect(!model.isHealthy)
        #expect(model.headline == "2 warnings")
    }

    @Test(arguments: [DemoScenario.dockStation, .unplugged])
    func healthyScenariosSayAllLinksHealthy(_ scenario: DemoScenario) {
        let model = HealthWidgetModel(Self.livePayload(scenario))
        #expect(model.findings.isEmpty)
        #expect(model.isHealthy)
        #expect(model.headline == "All links healthy")
    }

    @Test func ordersBySeverityThenHealthFindingsThenTitle() {
        func finding(_ kind: DiagnosticKind, _ severity: DiagnosticSeverity, _ title: String) -> Diagnostic {
            Diagnostic(id: "\(kind.rawValue):\(title)", kind: kind, severity: severity, title: title, detail: "")
        }
        var snapshot = S.snapshot(.travel)
        snapshot.diagnostics = [
            finding(.thunderboltBottleneck, .info, "A note"),
            finding(.usb2Fallback, .warning, "A drive is running at USB 2 speed"),
            finding(.speedRegression, .warning, "Z drive is running slower than before"),
            finding(.flakyConnection, .warning, "B keeps disconnecting"),
            finding(.liquidDetected, .critical, "Liquid in Left Front"),
        ]
        let model = HealthWidgetModel(WidgetPayload(snapshot: snapshot))
        #expect(model.findings.map(\.title) == ["Liquid in Left Front", "B keeps disconnecting",
                                                "Z drive is running slower than before",
                                                "A drive is running at USB 2 speed", "A note"])
        #expect(model.headline == "1 critical issue · 3 warnings · 1 note")
    }

    @Test func notesAloneStillReadAsHealthy() {
        var snapshot = S.snapshot(.travel)
        snapshot.diagnostics = [Diagnostic(id: "n", kind: .deepChain, severity: .info, title: "Note", detail: "")]
        #expect(HealthWidgetModel(WidgetPayload(snapshot: snapshot)).isHealthy)
    }

    @Test func likelyCauseIsLiftedOutOfTheDetail() {
        let hub = HealthWidgetModel.likelyCause(
            "3 devices behind Hub disconnected. Likely cause: the hub. It has no power supply of its own.")
        #expect(hub.cause == "Likely cause: the hub")
        #expect(hub.rest == "3 devices behind Hub disconnected. It has no power supply of its own.")
        let plain = HealthWidgetModel.likelyCause("iPhone is connected at 480 Mb/s.")
        #expect(plain.cause == nil)
        #expect(plain.rest == "iPhone is connected at 480 Mb/s.")
    }

    // MARK: The 7-day strip

    @Test func historyOffHasNoStripOrWeek() {
        let model = HealthWidgetModel(Self.livePayload(.flakyCable, keepsHistory: false))
        #expect(model.strip == nil)
        #expect(model.week == nil)
        #expect(model.events.isEmpty)
        // The findings do not come from the history.
        #expect(model.findings.first?.kind == .flakyConnection)
    }

    @Test func stripLeavesOutPortsWithoutCountersAndFollowsPhysicalOrder() throws {
        let payload = Self.livePayload(.studioDesk)
        let strip = try #require(HealthWidgetModel(payload).strip)
        // The HDMI port has no counters, so it would always read "No connections".
        #expect(strip.map(\.title) == ["Left Rear", "Left Center", "Left Front", "Right Center"])
        #expect(strip.allSatisfy { $0.days.count == 7 })
        #expect(HealthWidgetModel(payload).days.count == 7)
    }

    @Test func daysAndSummariesSayWhatHappened() throws {
        let strip = try #require(HealthWidgetModel(Self.withWeek(Self.livePayload(.studioDesk))).strip)
        #expect(strip[0].days.prefix(6) == [.quiet, .used, .used, .quiet, .used, .used])
        #expect(strip[0].summary == "8 connections")
        #expect(strip[1].days[2] == .problems)
        #expect(strip[1].summary == "2 problems")
        #expect(strip[2].days[4] == .critical)
        #expect(strip[2].summary == "Overcurrent")
        #expect(HealthWidgetModel.summary([PortHealth()]) == "No connections")
    }

    @Test func weekTotalsThePorts() {
        let model = HealthWidgetModel(Self.withWeek(Self.livePayload(.studioDesk)))
        // The third problem is today's: the drive that fell back to USB 2.
        #expect(model.week == "Last 7 days: 56 connections · 3 problems")
    }

    // MARK: Review images

    /// Writes every case to PNG for a visual check, when `BUSSTOP_WIDGET_REVIEW` names a folder.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BUSSTOP_WIDGET_REVIEW"] != nil))
    func writesReviewImages() throws {
        let folder = URL(filePath: try #require(ProcessInfo.processInfo.environment["BUSSTOP_WIDGET_REVIEW"]))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var cases: [(String, WidgetTimeline.Entry)] = DemoScenario.allCases.flatMap { scenario in
            [(scenario.rawValue, Self.entry(Self.withWeek(Self.livePayload(scenario)))),
             ("\(scenario.rawValue)-supportPayload", S.entry(scenario))]
        }
        cases.append(("historyOff", Self.entry(Self.livePayload(.flakyCable, keepsHistory: false))))
        cases.append(("crowded", Self.entry(Self.crowded())))
        cases.append(("notesOnly", Self.entry(Self.notesOnly())))
        cases.append(("todayOnly", Self.entry(Self.livePayload(.flakyCable))))
        cases.append(("stale", WidgetTimeline.Entry(date: S.date, state: .stale, payload: Self.livePayload(.travel))))
        for (name, entry) in cases {
            for (family, widgetFamily) in Self.families {
                for scheme in [ColorScheme.light, .dark] {
                    for vibrant in [false, true] where !vibrant || scheme == .dark {
                        let view = Self.view(entry, widgetFamily)
                            .environment(\.widgetRenderingMode, vibrant ? .vibrant : .fullColor)
                            .frame(width: family.size.width, height: family.size.height)
                            .padding(16)
                            .background(Lagoon.background)
                            .grayscale(vibrant ? 1 : 0)
                            .environment(\.colorScheme, scheme)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 2
                        let image = try #require(renderer.cgImage)
                        let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                        let suffix = vibrant ? "vibrant" : "\(scheme)"
                        try data.write(to: folder.appending(path: "\(name)-\(family.rawValue)-\(suffix).png"))
                    }
                }
            }
        }
    }
}
