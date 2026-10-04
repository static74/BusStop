import BusStopCore
import SwiftUI

/// Content of the menu bar popover (docs/SPEC.md §3.2).
///
/// Fixed at `Lagoon.popoverWidth` (wider for Large and Extra Large text, see
/// `Lagoon.popoverWidth(for:)`). The header and footer stay put; the
/// middle scrolls. The view measures its parts and grows with the content up
/// to `Lagoon.popoverMaxHeight`; the hosting controller passes that size to
/// the popover as its preferred content size.
struct PopoverView: View {
    var store: PortStore

    // First-pass guesses; replaced by measurements on the first layout.
    @State private var headerHeight: CGFloat = 64
    @State private var footerHeight: CGFloat = 52
    @State private var contentHeight: CGFloat = 360

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settings: AppSettings { store.settings }

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(store: store)
                .onHeightChange { headerHeight = $0 }
            Hairline()
            ScrollView(.vertical) {
                content
                    .onHeightChange { contentHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .frame(height: scrollHeight)
            Hairline()
            PopoverFooter(store: store)
                .onHeightChange { footerHeight = $0 }
        }
        .frame(width: Lagoon.popoverWidth(for: settings.textSize))
        .background(LagoonBackground(opacity: settings.backgroundOpacity))
        .preferredColorScheme(.dark)
        .tint(Lagoon.accent)
        // macOS ignores dynamicTypeSize, so the Text Size setting scales every
        // lagoonFont below through the environment instead.
        .lagoonTextScale(settings.textSize)
    }

    /// The scroll area shows all content until the popover reaches its
    /// maximum height, then scrolls.
    private var scrollHeight: CGFloat {
        let available = Lagoon.popoverMaxHeight - headerHeight - footerHeight - 2
        return max(80, min(contentHeight, available))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.hasLoaded {
                loading
            } else {
                PowerStripView(store: store)

                let diagnostics = DiagnosticsBanner.relevant(store.snapshot.diagnostics)
                if !diagnostics.isEmpty {
                    DiagnosticsBanner(diagnostics: diagnostics)
                        .transition(.opacity)
                }

                if store.snapshot.ports.isEmpty {
                    noPorts
                } else {
                    portList
                }

                OtherDevicesSection(store: store)
                DisplaysSection(store: store)
            }
        }
        .padding(12)
        .animation(reduceMotion ? nil : DeviceRowTransition.spring, value: store.hasLoaded)
    }

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Reading ports\u{2026}")
                .lagoonFont(.callout)
                .foregroundStyle(Lagoon.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }

    private var noPorts: some View {
        EmptyStateView(
            systemName: "cable.connector",
            title: "Port details unavailable",
            message: "This Mac does not report its port controllers, so Bus Stop cannot show "
                + "individual ports. Devices it can see are listed below."
        )
        .frame(height: 190)
        .lagoonCard()
    }

    private var portList: some View {
        let snapshot = store.snapshot
        let ports = store.visiblePorts
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Ports",
                          trailing: "\(snapshot.connectedPorts.count)/\(snapshot.ports.count) in use")
            if ports.isEmpty {
                Text("Nothing is connected. Empty ports are hidden in Settings.")
                    .lagoonFont(.caption)
                    .foregroundStyle(Lagoon.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lagoonCard()
            }
            ForEach(ports) { port in
                PortCardView(port: port, store: store)
            }
        }
    }
}

/// A one-pixel turquoise separator.
private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Lagoon.stroke)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
