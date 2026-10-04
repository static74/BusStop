import BusStopCore
import SwiftUI

/// Top of the popover: machine name, a one-line summary (with the DEMO badge
/// in demo mode) and the glass control cluster (Refresh, Open Topology,
/// Settings). The only glass in the popover besides the footer button
/// (docs/SPEC.md §4.1).
///
/// The name has the full width next to the controls and wraps to a second
/// line, so long marketing names such as "MacBook Pro (14-inch, 2026, M5 Pro)"
/// keep their chip instead of being cut off.
struct PopoverHeader: View {
    var store: PortStore

    var body: some View {
        let snapshot = store.snapshot
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.machine.name)
                    .lagoonFont(.title3, weight: .bold)
                    .foregroundStyle(Lagoon.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(snapshot.machine.name)
                HStack(spacing: 6) {
                    Text(store.hasLoaded ? PopoverText.summary(for: snapshot) : "Reading ports\u{2026}")
                        .lagoonFont(.caption, monospacedDigits: true)
                        .foregroundStyle(Lagoon.textSecondary)
                        .lineLimit(1)
                    if store.settings.demoMode {
                        DemoBadge()
                            .fixedSize()
                    }
                }
            }
            .layoutPriority(1)
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
