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
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Lagoon.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                WindowManager.shared.showTopology()
            } label: {
                Label("Open Topology", systemImage: "point.3.connected.trianglepath.dotted")
                    .labelStyle(.titleAndIcon)
                    .font(.callout.weight(.semibold))
                    // Near-white on the deep turquoise fill keeps the label legible.
                    .foregroundStyle(Lagoon.textPrimary)
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
