import BusStopCore
import BusStopUI
import SwiftUI
import WidgetKit

/// Diagnostics and flaky connections; Extra Large adds recent events and a 7-day strip per port.
struct HealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.github.static74.busstop.health", provider: PayloadProvider()) { entry in
            HealthWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Health")
        .description("Connection problems in plain English, with their likely cause.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

/// Reads the family, which only the widget's own environment knows.
private struct HealthWidgetEntryView: View {
    let entry: WidgetTimeline.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LagoonTheme.use(presetNamed: entry.payload?.colorPreset)
        return HealthWidgetView(entry: entry, family: family)
    }
}
