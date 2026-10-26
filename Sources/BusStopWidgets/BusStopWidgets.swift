import BusStopCore
import SwiftUI
import WidgetKit

extension WidgetTimeline.Entry: TimelineEntry {}

/// Reads the payload the app left in the App Group container. The app asks
/// for a reload whenever it writes; the timeline also reads it again when its
/// data goes stale, in case the system held a reload back.
struct PayloadProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetTimeline.Entry {
        WidgetTimeline.Entry(date: .now, state: .empty, payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetTimeline.Entry) -> Void) {
        completion(entries(now: .now)[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetTimeline.Entry>) -> Void) {
        let now = Date.now
        let entries = entries(now: now)
        completion(Timeline(entries: entries, policy: .after(WidgetTimeline.reloadDate(for: entries, now: now))))
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
