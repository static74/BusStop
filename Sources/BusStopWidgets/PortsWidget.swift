import BusStopCore
import BusStopUI
import SwiftUI
import WidgetKit

/// Every port in physical order, with what is plugged in, its speed and power.
struct PortsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.github.static74.busstop.ports", provider: PayloadProvider()) { entry in
            PortsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Ports")
        .description("Every port, what is plugged into it, its speed and its power.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

/// Reads the family, which only WidgetKit can set.
private struct PortsWidgetEntryView: View {
    let entry: WidgetTimeline.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        PortsWidgetView(entry: entry, family: family)
    }
}
