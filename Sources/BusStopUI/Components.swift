import BusStopCore
import SwiftUI

// Shared building blocks for the popover, the topology window, settings and
// the widgets. Content cards are solid Lagoon surfaces; Liquid Glass is
// reserved for controls (see docs/SPEC.md §4.1).

// MARK: - Cards

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
    /// Solid Lagoon card with a thin turquoise hairline.
    public func lagoonCard(highlighted: Bool = false, padding: CGFloat = 12) -> some View {
        modifier(LagoonCardModifier(isHighlighted: highlighted, padding: padding))
    }
}

// MARK: - Chips and badges

/// Capsule showing a link's speed, coloured by speed tier (the accent when the rate is unknown).
///
/// The capsule's fill and outline use the link-speed ramp; the text uses
/// `Lagoon.linkTextColor`, which stays legible for the slowest tiers. Under
/// Increase Contrast the text is primary and the outline stronger.
public struct SpeedChip: View {
    public var link: LinkInfo
    /// Compact shows only the rate ("10 Gb/s"); full shows "USB 3.2 Gen 2 @ 10 Gb/s".
    public var compact: Bool = true

    @Environment(\.colorSchemeContrast) private var contrast

    public init(link: LinkInfo, compact: Bool = true) {
        self.link = link
        self.compact = compact
    }

    public var body: some View {
        let tier = link.tier
        let color = tier.map { Lagoon.linkColor($0) } ?? Lagoon.accent
        let isIncreased = contrast == .increased
        let textColor = isIncreased ? Lagoon.textPrimary : (tier.map { Lagoon.linkTextColor($0) } ?? Lagoon.accent)
        Text(compact ? (link.rateLabel ?? link.generation) : link.label)
            .lagoonFont(.caption, weight: .semibold, design: .rounded, monospacedDigits: true)
            .lineLimit(1)
            .foregroundStyle(textColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(isIncreased ? 0.8 : 0.35),
                                            lineWidth: isIncreased ? 1 : 0.75))
            .chipHelp(Self.helpText(link), id: "speed")
            .accessibilityLabel(Text(link.label))
    }

    /// "USB 3.2 Gen 2 @ 10 Gb/s".
    public static func helpText(_ link: LinkInfo) -> String {
        link.label
    }
}

/// Capsule naming an active transport, with its speed when known. Colours
/// follow the same rules as `SpeedChip`.
public struct TransportChip: View {
    public var transport: TransportInfo

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    public init(transport: TransportInfo) {
        self.transport = transport
    }

    public var body: some View {
        let tier = transport.link?.tier
        let color = tier.map { Lagoon.linkColor($0) } ?? Lagoon.accent
        let isIncreased = contrast == .increased
        let textColor = isIncreased ? Lagoon.textPrimary : (tier.map { Lagoon.linkTextColor($0) } ?? Lagoon.accent)
        // The rate is a little softer than the name only where the colour is
        // bright enough to stay legible that way.
        let rateOpacity = !isIncreased && (tier ?? .legacy) >= .gbps10 ? 0.8 : 1
        HStack(spacing: 4) {
            Text(transport.kind.displayName)
            if let rate = transport.link?.rateLabel {
                Text(rate).foregroundStyle(textColor.opacity(Lagoon.textFade(rateOpacity, colorScheme)))
            }
        }
        .lagoonFont(.caption, weight: .semibold, design: .rounded, monospacedDigits: true)
        .lineLimit(1)
        .foregroundStyle(textColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(color.opacity(0.10)))
        .overlay(Capsule().strokeBorder(color.opacity(isIncreased ? 0.8 : 0.30), lineWidth: isIncreased ? 1 : 0.75))
        .chipHelp(Self.helpText(transport), id: "transport:\(transport.kind.rawValue)")
    }

    /// The transport's link ("USB 3.2 Gen 2 @ 10 Gb/s"), or its name when
    /// the link is unknown.
    public static func helpText(_ transport: TransportInfo) -> String {
        transport.link?.label ?? transport.kind.displayName
    }
}

/// "↓ 61 W" (into the Mac) or "↑ 4.5 W" (out to a device).
public struct PowerBadge: View {
    public var milliwatts: Int
    public var direction: PowerDirection
    /// Budgets and contracts are shown slightly dimmer than measurements
    /// (Dark only; in Light the help text tells them apart).
    public var isMeasured: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    public init(milliwatts: Int, direction: PowerDirection, isMeasured: Bool = true) {
        self.milliwatts = milliwatts
        self.direction = direction
        self.isMeasured = isMeasured
    }

    public var body: some View {
        let color = Lagoon.powerColor(direction)
        HStack(spacing: 3) {
            Image(systemName: arrowName)
                .lagoonFont(size: 9, weight: .bold)
            Text(Format.power(milliwatts: milliwatts))
        }
        .lagoonFont(.caption, weight: .semibold, design: .rounded, monospacedDigits: true)
        .foregroundStyle(color.opacity(Lagoon.textFade(isMeasured ? 1 : 0.75, colorScheme)))
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(color.opacity(0.10)))
        .chipHelp(helpText, id: "power")
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
        Self.helpText(milliwatts: milliwatts, direction: direction, isMeasured: isMeasured)
    }

    /// "61 W into the Mac", "4.5 W to devices (allocated)".
    public static func helpText(milliwatts: Int, direction: PowerDirection, isMeasured: Bool) -> String {
        let watts = Format.power(milliwatts: milliwatts)
        switch direction {
        case .input: return "\(watts) into the Mac" + (isMeasured ? "" : " (contract)")
        case .output: return "\(watts) to devices" + (isMeasured ? "" : " (allocated)")
        case .none: return watts
        }
    }
}

extension EnvironmentValues {
    /// False on the map, where chips publish a `GraphTooltipRegion` for the
    /// map's own tooltip instead of using the system's (see `GraphTooltips.swift`).
    @Entry public var showsChipHelp = true
}

/// A chip's explanation on hover: the system tooltip, or on the map (where
/// `showsChipHelp` is false) a region for the map's own tooltip.
struct ChipHelpModifier: ViewModifier {
    var text: String
    /// Names the chip within its card or link.
    var id: String
    @Environment(\.showsChipHelp) private var showsChipHelp

    func body(content: Content) -> some View {
        if showsChipHelp {
            content.help(text)
        } else {
            content.graphTooltip(text, id: id)
        }
    }
}

extension View {
    public func chipHelp(_ text: String, id: String) -> some View {
        modifier(ChipHelpModifier(text: text, id: id))
    }
}

// MARK: - Map tooltip regions

/// A chip or badge on the map and its tooltip, in layout coordinates. The
/// map's tooltip itself (`GraphTooltip`, `GraphTooltipState`) is in the app.
public nonisolated struct GraphTooltipRegion: Equatable, Sendable {
    /// Unique on the map: the card or link, then the chip ("port:3/power").
    public var id: String
    public var text: String
    public var rect: CGRect

    public init(id: String, text: String, rect: CGRect) {
        self.id = id
        self.text = text
        self.rect = rect
    }

    /// The coordinate space of one card (or one link chip) before the zoom
    /// (`GraphTooltip.space` in the app).
    public static let space = "graphTooltipSpace"
}

/// Every chip on the map that has a tooltip.
public nonisolated struct GraphTooltipRegionsKey: PreferenceKey {
    public static let defaultValue: [GraphTooltipRegion] = []

    public static func reduce(value: inout [GraphTooltipRegion], nextValue: () -> [GraphTooltipRegion]) {
        value += nextValue()
    }
}

extension View {
    /// Publishes this view as a tooltip region, measured in the enclosing
    /// `GraphTooltip.space`.
    public func graphTooltip(_ text: String, id: String) -> some View {
        modifier(GraphTooltipModifier(text: text, id: id))
    }
}

/// Keeps the view's rectangle in `GraphTooltip.space` and publishes it.
/// That rectangle moves only when the card's content does, not when the map
/// pans or zooms, so nothing here runs for a frame of a pan or zoom.
struct GraphTooltipModifier: ViewModifier {
    var text: String
    var id: String
    @State private var rect: CGRect?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GraphTooltipRegion.space)) } action: { rect = $0 }
            .preference(key: GraphTooltipRegionsKey.self,
                        value: rect.map { [GraphTooltipRegion(id: id, text: text, rect: $0)] } ?? [])
    }
}

/// Ring that glows turquoise when something is connected (the glow is Dark only).
public struct StatusRing: View {
    public var isActive: Bool
    public var size: CGFloat = 12

    public init(isActive: Bool, size: CGFloat = 12) {
        self.isActive = isActive
        self.size = size
    }

    public var body: some View {
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
        .lagoonGlow(isActive ? Lagoon.accent.opacity(0.6) : .clear, radius: isActive ? 4 : 0)
        .accessibilityHidden(true)
    }
}

/// A soft coloured shadow in Dark; nothing in Light, where blur reads as
/// smudge (docs/decisions.md).
struct LagoonGlowModifier: ViewModifier {
    var color: Color
    var radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.shadow(color: colorScheme == .dark ? color : .clear, radius: colorScheme == .dark ? radius : 0)
    }
}

extension View {
    /// `.shadow(color:radius:)` drawn in Dark only.
    public func lagoonGlow(_ color: Color, radius: CGFloat) -> some View {
        modifier(LagoonGlowModifier(color: color, radius: radius))
    }
}

/// Icon tile for a device kind.
public struct DeviceIcon: View {
    public var kind: DeviceKind
    public var size: CGFloat = 22
    public var dimmed: Bool = false

    public init(kind: DeviceKind, size: CGFloat = 22, dimmed: Bool = false) {
        self.kind = kind
        self.size = size
        self.dimmed = dimmed
    }

    public var body: some View {
        Image(systemName: kind.symbolName)
            .lagoonFont(size: size * 0.52, weight: .medium)
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
public struct PortIcon: View {
    public var kind: PortKind
    public var isActive: Bool
    public var size: CGFloat = 26

    public init(kind: PortKind, isActive: Bool, size: CGFloat = 26) {
        self.kind = kind
        self.isActive = isActive
        self.size = size
    }

    public var body: some View {
        Image(systemName: kind.symbolName)
            .lagoonFont(size: size * 0.5, weight: .semibold)
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
public struct Sparkline: View {
    public var values: [Double]
    public var color: Color = Lagoon.accent
    public var lineWidth: CGFloat = 1.5

    public init(values: [Double], color: Color = Lagoon.accent, lineWidth: CGFloat = 1.5) {
        self.values = values
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
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
