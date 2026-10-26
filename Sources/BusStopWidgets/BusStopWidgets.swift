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

// shortcut: a placeholder that only proves the data path; replace it with the real widgets.
struct HelloView: View {
    let entry: WidgetTimeline.Entry

    var body: some View {
        VStack(spacing: 6) {
            switch entry.state {
            case .empty:
                Text("Open Bus Stop")
            case .stale:
                Text("Bus Stop isn't running")
            case .live, .demo:
                if entry.state == .demo { Text("Demo").font(.caption.bold()) }
                if let payload = entry.payload {
                    Text("\(payload.snapshot.ports.count) ports · updated \(payload.capturedAt, style: .relative) ago")
                }
            }
        }
        .font(.title2)
        .multilineTextAlignment(.center)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct HelloWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.github.static74.busstop.hello", provider: PayloadProvider()) { entry in
            HelloView(entry: entry)
        }
        .configurationDisplayName("Bus Stop")
        .description("Your ports, from Bus Stop.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

@main
struct BusStopWidgetBundle: WidgetBundle {
    var body: some Widget {
        HelloWidget()
        PowerWidget()
    }
}
