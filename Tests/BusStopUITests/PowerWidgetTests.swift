import AppKit
import BusStopCore
import SwiftUI
import Testing
import WidgetKit
@testable import BusStopUI

@Suite("Power widget")
@MainActor
struct PowerWidgetTests {
    typealias S = WidgetTestSupport

    static func widgetFamily(_ family: S.Family) -> WidgetFamily {
        family == .large ? .systemLarge : .systemExtraLarge
    }

    static func view(_ scenario: DemoScenario, _ family: S.Family,
                     state: WidgetTimeline.State = .demo) -> PowerWidgetView {
        PowerWidgetView(entry: S.entry(scenario, state: state), family: widgetFamily(family))
    }

    // MARK: Rendering

    @Test(arguments: DemoScenario.allCases)
    func rendersEveryScenario(_ scenario: DemoScenario) throws {
        for family in S.Family.allCases {
            for scheme in [ColorScheme.dark, .light] {
                #expect(S.hasContent(try S.render(Self.view(scenario, family), family, colorScheme: scheme)),
                        "\(scenario) \(family) \(scheme)")
            }
            let vibrant = Self.view(scenario, family).environment(\.widgetRenderingMode, .vibrant)
            #expect(S.hasContent(try S.render(vibrant, family)), "\(scenario) \(family) vibrant")
        }
    }

    /// The content's natural height, with the charts at their minimum, fits
    /// the widget, so nothing is pushed out of the frame.
    @Test(arguments: DemoScenario.allCases)
    func fitsEveryScenario(_ scenario: DemoScenario) {
        for family in S.Family.allCases {
            let host = NSHostingController(rootView: Self.view(scenario, family)
                .frame(width: family.size.width)
                .fixedSize(horizontal: false, vertical: true))
            let height = host.sizeThatFits(in: CGSize(width: family.size.width, height: 10_000)).height
            #expect(height <= family.size.height, "\(scenario) \(family): \(height)")
        }
    }

    @Test(arguments: [WidgetTimeline.State.empty, .stale])
    func rendersOtherStates(_ state: WidgetTimeline.State) throws {
        let entry = state == .empty
            ? WidgetTimeline.Entry(date: S.date, state: .empty, payload: nil)
            : S.entry(.studioDesk, state: state)
        for family in S.Family.allCases {
            let view = PowerWidgetView(entry: entry, family: Self.widgetFamily(family))
            #expect(S.hasContent(try S.render(view, family), fraction: 0.001), "\(state) \(family)")
        }
    }

    // MARK: Chart data

    @Test func hourJoinsDayStepsAndLiveMinutes() throws {
        let payload = S.payload(.studioDesk)
        let values = PowerWidgetData.hourValues(.input, payload)
        let liveStart = try #require(payload.recentPower.first?.date)
        let older = values.filter { $0.date < liveStart - 60 }
        // The day's 5-minute steps from an hour ago up to the live buffer: 60 to 15 minutes back.
        #expect(older.count == 10)
        #expect(older.allSatisfy { $0.date + WidgetPayload.dayPowerStep <= liveStart })
        // Ten minutes of 5-second samples become one point per clock minute.
        #expect((10...11).contains(values.count - older.count))
        #expect(zip(values, values.dropFirst()).allSatisfy { $0.date < $1.date })
        #expect(values.allSatisfy { $0.date >= payload.capturedAt - 3_600 && $0.date <= payload.capturedAt })
        // One line: the gaps between steps are inside the join limit.
        let points = PowerWidgetData.points(payload, range: .hour).filter { $0.series == "In" }
        #expect(Set(points.map(\.segment)) == [0])
    }

    @Test func minuteMeansAverageEachMinute() {
        let base = Date(timeIntervalSinceReferenceDate: 600)
        let values = [(base, 10.0), (base + 20, 20.0), (base + 59, 30.0), (base + 60, 5.0)]
            .map { (date: $0.0, watts: $0.1) }
        let means = PowerWidgetData.minuteMeans(values)
        #expect(means.map(\.date) == [base, base + 60])
        #expect(means.map(\.watts) == [20, 5])
    }

    @Test func axisUsesRoundClockTimes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        // The test date is 14:13:20 UTC.
        let hour = PowerWidgetData.axisDates(.hour, end: S.date, calendar: calendar)
        #expect(hour.map { calendar.component(.minute, from: $0) } == [15, 30, 45, 0])
        let day = PowerWidgetData.axisDates(.day, end: S.date, calendar: calendar)
        #expect(day.map { calendar.component(.hour, from: $0) } == [18, 0, 6, 12])
    }

    @Test func dayCoversTheDayPayload() {
        let payload = S.payload(.travel)
        #expect(PowerWidgetData.dayValues(.load, payload).count == 288)
        #expect(PowerWidgetData.spanText(PowerWidgetData.points(payload, range: .day), range: .day,
                                         end: payload.capturedAt) == "Last 24 hours")
    }

    @Test func spanSaysWhenTheHourIsShort() {
        var payload = S.payload(.studioDesk)
        payload.dayPower = []
        let points = PowerWidgetData.points(payload, range: .hour)
        #expect(!points.isEmpty)
        #expect(PowerWidgetData.spanText(points, range: .hour, end: payload.capturedAt).hasPrefix("Since "))
        #expect(PowerWidgetData.spanText(PowerWidgetData.points(S.payload(.studioDesk), range: .hour),
                                         range: .hour, end: payload.capturedAt) == "Last hour")
    }

    @Test func seriesFollowWhatTheMacReports() {
        #expect(PowerWidgetData.series(S.payload(.studioDesk)) == [.input, .load])
        #expect(PowerWidgetData.series(S.payload(.unplugged)) == [.load])
        #expect(PowerWidgetData.series(S.payload(.dockStation)) == [.devices])
        #expect(PowerWidgetData.dayValues(.devices, S.payload(.dockStation)).allSatisfy { $0.watts > 0 })
    }

    // MARK: Text

    @Test func chargerShowsItsContract() {
        let source = PowerWidgetText.source(S.snapshot(.studioDesk))
        #expect(source.title == "140W USB-C Power Adapter")
        #expect(source.detail.hasPrefix("28 V × 5 A"))
        #expect(PowerWidgetText.source(S.snapshot(.travel)).detail.hasPrefix("20 V × 3.5 A"))
    }

    @Test func noChargerSaysWhatPowersTheMac() {
        #expect(PowerWidgetText.source(S.snapshot(.unplugged)).title == "No charger")
        #expect(PowerWidgetText.source(S.snapshot(.dockStation)).title == "Mains power")
    }

    @Test func figuresPerScenario() {
        let desk = PowerWidgetText.figures(S.snapshot(.studioDesk))
        #expect(desk.map(\.label) == ["In", "Battery", "Load", "Out"])
        #expect(desk.first?.value == "62 W")
        #expect(desk[1].value == "76%" && desk[1].detail == "Charging")
        #expect(PowerWidgetText.figures(S.snapshot(.unplugged)).map(\.label) == ["Battery", "Load", "Out"])
        #expect(PowerWidgetText.figures(S.snapshot(.dockStation)).map(\.label) == ["Out", "USB budget"])
    }

    @Test func poweredPortsInPhysicalOrder() {
        let snapshot = S.snapshot(.dockStation)
        let keys = PowerWidgetText.poweredPorts(snapshot).map(\.key)
        #expect(keys.count == 2)
        #expect(keys == snapshot.ports.map(\.key).filter(keys.contains))
        #expect(PowerWidgetText.poweredPorts(S.snapshot(.unplugged)).isEmpty)
    }

    // MARK: Review images

    /// Writes every scenario, family and appearance to PNG files for a visual
    /// check, when `WIDGET_REVIEW_DIR` is set. The widget's background is
    /// drawn in, since tests have no container to draw it; "vibrant" fakes
    /// the desktop's monochrome rendering by turning luminance into opacity.
    @Test func writeReviewImages() throws {
        guard let directory = ProcessInfo.processInfo.environment["WIDGET_REVIEW_DIR"] else { return }
        let folder = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for scenario in DemoScenario.allCases {
            for family in S.Family.allCases {
                let size = family.size
                func write(_ view: some View, _ name: String) throws {
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try #require(renderer.cgImage)
                    let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    let file = "\(scenario.rawValue)-\(family.rawValue)-\(name).png"
                    try png.write(to: folder.appendingPathComponent(file))
                }
                for scheme in [ColorScheme.dark, .light] {
                    try write(Self.view(scenario, family)
                        .frame(width: size.width, height: size.height)
                        .padding(16)
                        .background(Lagoon.background)
                        .environment(\.colorScheme, scheme), scheme == .dark ? "dark" : "light")
                }
                // The same widget if the system's content margins come out of the family size.
                try write(Self.view(scenario, family)
                    .frame(width: size.width - 32, height: size.height - 32)
                    .padding(16)
                    .background(Lagoon.background)
                    .environment(\.colorScheme, .dark), "tight")
                let vibrant = ZStack {
                    Color.black
                    Self.view(scenario, family).environment(\.widgetRenderingMode, .vibrant)
                }
                .frame(width: size.width, height: size.height)
                .padding(16)
                .environment(\.colorScheme, .dark)
                try write(ZStack {
                    Color(white: 0.3)
                    Color(white: 0.95).mask(vibrant.compositingGroup().luminanceToAlpha())
                }.frame(width: size.width + 32, height: size.height + 32), "vibrant")
            }
        }
    }
}
