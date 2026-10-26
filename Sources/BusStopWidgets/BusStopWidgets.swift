import BusStopCore
import SwiftUI
import WidgetKit

extension WidgetTimeline.Entry: TimelineEntry {}

/// Reads the payload the app left in the App Group container. The app asks
/// for a reload whenever it writes, so the timeline itself never refreshes.
struct PayloadProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetTimeline.Entry {
        WidgetTimeline.Entry(date: .now, state: .empty, payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetTimeline.Entry) -> Void) {
        completion(entries(now: .now)[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetTimeline.Entry>) -> Void) {
        completion(Timeline(entries: entries(now: .now), policy: .never))
    }

    private func entries(now: Date) -> [WidgetTimeline.Entry] {
        WidgetTimeline.entries(payload: WidgetPayloadFile.appGroup()?.read(), now: now)
    }
}

@main
struct BusStopWidgetBundle: WidgetBundle {
    var body: some Widget {
        PortsWidget()
        PowerWidget()
        HealthWidget()
    }
}
