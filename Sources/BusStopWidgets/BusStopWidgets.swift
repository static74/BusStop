import SwiftUI
import WidgetKit

// shortcut: a placeholder that only proves the extension loads; replace it with the real widgets.
struct HelloEntry: TimelineEntry {
    let date: Date
}

struct HelloProvider: TimelineProvider {
    func placeholder(in context: Context) -> HelloEntry { HelloEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (HelloEntry) -> Void) {
        completion(HelloEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HelloEntry>) -> Void) {
        completion(Timeline(entries: [HelloEntry(date: .now)], policy: .never))
    }
}

struct HelloWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.github.static74.busstop.hello", provider: HelloProvider()) { _ in
            Text("Hello, world")
                .font(.title)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Bus Stop")
        .description("Hello, world.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}

@main
struct BusStopWidgetBundle: WidgetBundle {
    var body: some Widget {
        HelloWidget()
    }
}
