import AppKit
import BusStopCore
import SwiftUI
import Testing

/// Shared helpers for the widget view tests: a payload per demo scenario and
/// an offscreen render at the desktop widget sizes.
enum WidgetTestSupport {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    /// Desktop widget sizes on macOS 26, in points.
    enum Family: String, CaseIterable, Sendable {
        case large, extraLarge

        var size: CGSize {
            switch self {
            case .large: CGSize(width: 344, height: 344)
            case .extraLarge: CGSize(width: 716, height: 344)
            }
        }
    }

    static func snapshot(_ scenario: DemoScenario, tick: Int = 0) -> HostSnapshot {
        TopologyBuilder.build(scenario.raw(at: date, tick: tick), options: BuildOptions(isDemo: true))
    }

    /// A payload like the app writes for `scenario`: power over the last ten
    /// minutes and the day, built from successive demo ticks so the charts
    /// have shape, and the events those ticks produce after plugging
    /// everything in.
    static func payload(_ scenario: DemoScenario) -> WidgetPayload {
        let snapshot = snapshot(scenario)
        var events = SnapshotDiffer.events(from: self.snapshot(.unplugged), to: self.snapshot(scenario, tick: 0),
                                           at: date - 600)
        for tick in 1..<120 {
            events += SnapshotDiffer.events(from: self.snapshot(scenario, tick: tick - 1),
                                            to: self.snapshot(scenario, tick: tick), at: date - 600 + Double(tick) * 5)
        }
        let recent = (0..<120).map { tick in
            var sample = PowerSample(self.snapshot(scenario, tick: tick))
            sample.date = date - Double(120 - tick) * 5
            return sample
        }
        let day = (0..<288).map { step in
            var sample = PowerSample(self.snapshot(scenario, tick: step))
            sample.date = date - Double(288 - step) * WidgetPayload.dayPowerStep
            return sample
        }
        return WidgetPayload(snapshot: snapshot, recentPower: recent, dayPower: day,
                             events: events.reversed(), portHealth: [:])
    }

    static func entry(_ scenario: DemoScenario, state: WidgetTimeline.State = .demo) -> WidgetTimeline.Entry {
        WidgetTimeline.Entry(date: date, state: state, payload: payload(scenario))
    }

    /// Renders `view` at the family's size and returns the bitmap.
    @MainActor
    static func render(_ view: some View, _ family: Family, colorScheme: ColorScheme = .dark) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view
            .frame(width: family.size.width, height: family.size.height)
            .padding(16)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        return NSBitmapImageRep(cgImage: image)
    }

    /// True when more than `fraction` of the pixels differ from the corner
    /// pixel, so the view drew something.
    static func hasContent(_ bitmap: NSBitmapImageRep, fraction: Double = 0.01) -> Bool {
        guard let corner = bitmap.colorAt(x: 0, y: 0) else { return false }
        var differing = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) where bitmap.colorAt(x: x, y: y) != corner {
                differing += 1
            }
        }
        return Double(differing) / Double(bitmap.pixelsWide * bitmap.pixelsHigh / 4) > fraction
    }
}
