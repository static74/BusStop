import BusStopCore
import SwiftUI

/// Bottom of the popover: "Updated just now" and the prominent
/// "Open Topology" glass button.
struct PopoverFooter: View {
    var store: PortStore

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Text(updatedText(now: context.date))
                    .lagoonFont(.caption, monospacedDigits: true)
                    .foregroundStyle(Lagoon.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                WindowManager.shared.showTopology()
            } label: {
                Label("Open Topology", systemImage: "point.3.connected.trianglepath.dotted")
                    .labelStyle(.titleAndIcon)
                    .lagoonFont(.callout, weight: .semibold)
                    // Black on the deep turquoise fill reads at about 6.8:1, like
                    // the DEMO badge; near-white text there was below 3:1.
                    .foregroundStyle(Lagoon.background)
            }
            .buttonStyle(.glassProminent)
            .tint(Lagoon.accentDeep)
            .help("Open the topology window")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func updatedText(now: Date) -> String {
        guard let lastUpdated = store.lastUpdated else { return "Waiting for data" }
        return "Updated " + Format.relative(lastUpdated, now: now)
    }
}
