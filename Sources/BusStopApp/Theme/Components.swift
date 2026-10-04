import BusStopCore
import SwiftUI

// Shared building blocks for the popover, the topology window and settings.
// Content cards are solid near-black surfaces; Liquid Glass is reserved for
// controls (see docs/SPEC.md §4.1).

// MARK: - Backgrounds and cards

/// True-black backing at the user's chosen opacity. Under Reduce Transparency
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

struct LagoonCardModifier: ViewModifier {
    var isHighlighted: Bool = false
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Lagoon.cardRadius, style: .continuous)
                    .fill(isHighlighted ? Lagoon.surfaceRaised : Lagoon.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Lagoon.cardRadius, style: .continuous)
                    .strokeBorder(isHighlighted ? Lagoon.strokeStrong : Lagoon.stroke, lineWidth: 1)
            )
    }
}

extension View {
    /// Solid near-black card with a thin turquoise hairline.
    func lagoonCard(highlighted: Bool = false, padding: CGFloat = 12) -> some View {
        modifier(LagoonCardModifier(isHighlighted: highlighted, padding: padding))
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
                .font(.system(size: 13, weight: .semibold))
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

// MARK: - Chips and badges

/// Capsule showing a link's speed, coloured by speed tier.
struct SpeedChip: View {
    var link: LinkInfo
    /// Compact shows only the rate ("10 Gb/s"); full shows "USB 3.2 Gen 2 @ 10 Gb/s".
    var compact: Bool = true

    var body: some View {
        let color = Lagoon.linkColor(link.tier)
        Text(compact ? (link.rateLabel ?? link.generation) : link.label)
            .font(Lagoon.chipFont)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.75))
            .help(link.label)
            .accessibilityLabel(Text(link.label))
    }
}

/// Capsule naming an active transport, with its speed when known.
struct TransportChip: View {
    var transport: TransportInfo

    var body: some View {
        let color = transport.link.map { Lagoon.linkColor($0.tier) } ?? Lagoon.accent
        HStack(spacing: 4) {
            Text(transport.kind.displayName)
            if let rate = transport.link?.rateLabel {
                Text(rate).foregroundStyle(color.opacity(0.8))
            }
        }
        .font(Lagoon.chipFont)
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(color.opacity(0.10)))
        .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 0.75))
        .help(transport.link?.label ?? transport.kind.displayName)
    }
}

/// "↓ 61 W" (into the Mac) or "↑ 4.5 W" (out to a device).
struct PowerBadge: View {
    var milliwatts: Int
    var direction: PowerDirection
    /// Budgets and contracts are shown slightly dimmer than measurements.
    var isMeasured: Bool = true

    var body: some View {
        let color = Lagoon.powerColor(direction)
        HStack(spacing: 3) {
            Image(systemName: arrowName)
                .font(.system(size: 9, weight: .bold))
            Text(Format.power(milliwatts: milliwatts))
        }
        .font(Lagoon.chipFont)
        .monospacedDigit()
        .foregroundStyle(color.opacity(isMeasured ? 1 : 0.75))
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(color.opacity(0.10)))
        .help(helpText)
        .accessibilityLabel(Text(helpText))
    }

    private var arrowName: String {
        switch direction {
        case .input: return "arrow.down"
        case .output: return "arrow.up"
        case .none: return "bolt"
        }
    }

    private var helpText: String {
        let watts = Format.power(milliwatts: milliwatts)
        switch direction {
        case .input: return "\(watts) into the Mac" + (isMeasured ? "" : " (contract)")
        case .output: return "\(watts) to devices" + (isMeasured ? "" : " (allocated)")
        case .none: return watts
        }
    }
}

/// Ring that glows turquoise when something is connected.
struct StatusRing: View {
    var isActive: Bool
    var size: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isActive ? Lagoon.accent : Lagoon.accentMuted, lineWidth: size * 0.18)
            if isActive {
                Circle()
                    .fill(Lagoon.accent)
                    .padding(size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: isActive ? Lagoon.accent.opacity(0.6) : .clear, radius: isActive ? 4 : 0)
        .accessibilityHidden(true)
    }
}

/// Icon tile for a device kind.
struct DeviceIcon: View {
    var kind: DeviceKind
    var size: CGFloat = 22
    var dimmed: Bool = false

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: size * 0.52, weight: .medium))
            .foregroundStyle(dimmed ? Lagoon.textTertiary : Lagoon.accent)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Lagoon.accent.opacity(dimmed ? 0.04 : 0.10))
            )
            .accessibilityHidden(true)
    }
}

/// Icon tile for a port connector.
struct PortIcon: View {
    var kind: PortKind
    var isActive: Bool
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(isActive ? Lagoon.accent : Lagoon.textTertiary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(isActive ? Lagoon.accent.opacity(0.14) : Lagoon.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(isActive ? Lagoon.accent.opacity(0.45) : Lagoon.stroke, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Charts

/// A minimal line sparkline with a soft turquoise fill.
struct Sparkline: View {
    var values: [Double]
    var color: Color = Lagoon.accent
    var lineWidth: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            if points.count >= 2 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                }
            } else {
                Rectangle().fill(color.opacity(0.08)).frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .accessibilityHidden(true)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let minValue = min(values.min() ?? 0, 0)
        let maxValue = max(values.max() ?? 1, minValue + 0.001)
        let span = maxValue - minValue
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            let y = size.height - CGFloat((value - minValue) / span) * (size.height - lineWidth) - lineWidth / 2
            return CGPoint(x: CGFloat(index) * step, y: y)
        }
    }
}

// MARK: - Text rows

struct SectionHeader: View {
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .tracking(0.8)
                .foregroundStyle(Lagoon.textTertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Lagoon.textTertiary)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Label/value row for inspectors and detail panels.
struct KeyValueRow: View {
    var label: String
    var value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(Lagoon.textSecondary)
                .frame(minWidth: 110, alignment: .leading)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(Lagoon.textPrimary)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
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
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Lagoon.accent.opacity(0.7))
            Text(title)
                .font(Lagoon.titleFont)
                .foregroundStyle(Lagoon.textPrimary)
            Text(message)
                .font(.callout)
                .foregroundStyle(Lagoon.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small "DEMO" capsule shown while demo mode is on.
struct DemoBadge: View {
    var body: some View {
        Text("DEMO")
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundStyle(Lagoon.background)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Lagoon.accent))
            .help("Showing a demo scenario. Turn off in Settings › Advanced.")
    }
}
