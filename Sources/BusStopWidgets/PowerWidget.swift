import BusStopCore
import BusStopUI
import SwiftUI
import WidgetKit

/// Charger, battery and power over time.
struct PowerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.github.static74.busstop.power", provider: PayloadProvider()) { entry in
            PowerWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Power")
        .description("Your charger, battery and power use over time.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

/// Reads the family from the environment, which only the widget's own view can.
private struct PowerWidgetEntryView: View {
    let entry: WidgetTimeline.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LagoonTheme.use(presetNamed: entry.payload?.colorPreset)
        return PowerWidgetView(entry: entry, family: family)
    }
}
