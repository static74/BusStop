import BusStopCore
import BusStopUI
import SwiftUI

// The app's own building blocks; the ones the widgets share are in BusStopUI.

// MARK: - Backgrounds

/// The Lagoon background at the user's chosen opacity. Under Reduce Transparency
/// it is always fully opaque.
struct LagoonBackground: View {
    var opacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Lagoon.background
            .opacity(reduceTransparency ? 1 : opacity)
            .ignoresSafeArea()
    }
}

// MARK: - Glass controls

/// A circular glass icon button for header and toolbar clusters.
/// Place several inside one `GlassEffectContainer`.
struct GlassIconButton: View {
    var systemName: String
    var help: String
    /// Tint strength; nil uses the Appearance setting.
    var tint: Double? = nil
    var action: () -> Void

    var body: some View {
        let tintStrength = tint ?? AppSettings.shared.glassTint
        Button(action: action) {
            Image(systemName: systemName)
                .lagoonFont(size: 13, weight: .semibold)
                .foregroundStyle(Lagoon.textPrimary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Lagoon.accent.opacity(tintStrength)).interactive(), in: .circle)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Chips

/// The power across a link, or in a port, in its power tier's colour: "47 W"
/// for a port's reading, "≤4.5 W" for a USB power budget. Smaller than a
/// speed chip, since it hangs under one as the secondary fact; that also
/// leaves room between neighbouring pairs on the map.
struct PowerChip: View {
    var power: GraphEdgePower

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let tier = power.tier
        let color = Lagoon.powerColor(tier)
        let isIncreased = contrast == .increased
        let help = Self.helpText(power)
        Text(power.label)
            .lagoonFont(size: 9, weight: .semibold, design: .rounded, monospacedDigits: true)
            .lineLimit(1)
            .foregroundStyle(isIncreased ? Lagoon.textPrimary : Lagoon.powerTextColor(tier))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(isIncreased ? 0.8 : 0.35), lineWidth: isIncreased ? 1 : 0.75))
            .chipHelp(help, id: "power")
            .accessibilityLabel(Text(help))
    }

    /// "47 W into the Mac, measured", or "Up to 4.5 W budgeted for USB devices".
    static func helpText(_ power: GraphEdgePower) -> String {
        guard power.isMeasured else { return "Up to \(power.label.dropFirst()) budgeted for USB devices" }
        return power.label + (power.flowsToParent ? " into the Mac" : "") + ", measured"
    }
}

// MARK: - Text rows

struct SectionHeader: View {
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .lagoonFont(.caption, weight: .semibold)
                .foregroundStyle(Lagoon.textSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .lagoonFont(.caption2, monospacedDigits: true)
                    .foregroundStyle(Lagoon.textTertiary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Centered empty-state message.
struct EmptyStateView: View {
    var systemName: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemName)
                .lagoonFont(size: 34, weight: .light)
                .foregroundStyle(Lagoon.accent.opacity(0.7))
            Text(title)
                .lagoonFont(.headline, weight: .semibold)
                .foregroundStyle(Lagoon.textPrimary)
            Text(message)
                .lagoonFont(.callout)
                .foregroundStyle(Lagoon.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
