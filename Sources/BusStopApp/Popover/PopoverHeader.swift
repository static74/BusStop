import BusStopCore
import SwiftUI

/// Top of the popover: machine name, a one-line summary and the glass control
/// cluster (Refresh, Open Topology, Settings). The only glass in the popover
/// besides the footer button (docs/SPEC.md §4.1).
struct PopoverHeader: View {
    var store: PortStore

    var body: some View {
        let snapshot = store.snapshot
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(snapshot.machine.name)
                        .font(Lagoon.machineFont)
                        .foregroundStyle(Lagoon.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                        .help(snapshot.machine.name)
                    if store.settings.demoMode {
                        DemoBadge()
                    }
                }
                Text(store.hasLoaded ? PopoverText.summary(for: snapshot) : "Reading ports\u{2026}")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Lagoon.textSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 8) {
                    GlassIconButton(systemName: "arrow.clockwise", help: "Refresh") {
                        store.refresh()
                    }
                    GlassIconButton(systemName: "point.3.connected.trianglepath.dotted", help: "Open Topology") {
                        WindowManager.shared.showTopology()
                    }
                    GlassIconButton(systemName: "gearshape", help: "Settings") {
                        WindowManager.shared.showSettings()
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}
