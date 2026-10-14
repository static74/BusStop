import BusStopCore
import SwiftUI

// Layers drawn behind the graph's nodes: a dotted backdrop, the links, the
// travelling pulses (TimelineView + Canvas) and the speed chips. Each canvas
// is the size of the map view and draws through the `GraphCamera`, so links
// stay sharp at any zoom and only what is on screen is drawn.

nonisolated extension GraphCurve {
    var path: Path {
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }
}

/// How one edge is painted, resolved from the Lagoon tokens. Nonisolated,
/// because the Canvas renderers that draw it are.
nonisolated struct GraphEdgeStroke: Identifiable {
    var id: String
    var path: Path
    var end: CGPoint
    var color: Color
    var width: CGFloat
    var dash: [CGFloat]
    var glows: Bool
    var opacity: Double
    /// Trunks get no socket dot at the port end.
    var drawsSocket: Bool
    /// The smallest socket dot, in the same units as `width`.
    var minimumSocketRadius: CGFloat = 2.2
    /// `color` at `opacity`, pre-blended with the background into a solid
    /// colour, so two strokes that overlap look like one.
    var solidColor: Color

    /// The dot where the link meets the child's card.
    var socketPath: Path {
        let radius = max(minimumSocketRadius, width * 0.95)
        return Path(ellipseIn: CGRect(x: end.x - radius, y: end.y - radius, width: radius * 2, height: radius * 2))
    }

    /// This stroke as seen through `camera`: path, width, dash and socket in
    /// view points.
    func viewed(through camera: GraphCamera) -> GraphEdgeStroke {
        var stroke = self
        stroke.path = path.applying(camera.transform)
        stroke.end = camera.screenPoint(end)
        stroke.width = width * camera.scale
        stroke.dash = dash.map { $0 * camera.scale }
        stroke.minimumSocketRadius = minimumSocketRadius * camera.scale
        return stroke
    }
}

/// One moving pulse track along an edge.
struct GraphPulseTrack: Identifiable {
    var id: String
    var curve: GraphCurve
    var color: Color
    var radius: CGFloat
    /// Seconds for one dot to travel the whole edge.
    var period: Double
    /// 0…1, so neighbouring edges do not pulse in lockstep.
    var phase: Double
    var dots: Int
}

/// Turns layout edges into strokes and pulse tracks.
enum GraphPaint {
    static func strokes(for layout: GraphLayout, dimmed: Set<String>) -> [GraphEdgeStroke] {
        layout.edges.map { edge in
            let dimFactor = dimmed.contains(edge.toID) ? 0.22 : 1
            switch edge.kind {
            case .trunk:
                let color = edge.isActive ? Lagoon.accent : Lagoon.accentMuted
                let opacity = (edge.isActive ? 0.42 : 0.7) * dimFactor
                return GraphEdgeStroke(
                    id: edge.id,
                    path: edge.curve.path,
                    end: edge.curve.end,
                    color: color,
                    width: edge.isActive ? 1.4 : 1,
                    dash: edge.isDashed ? [3, 4] : [],
                    glows: false,
                    opacity: opacity,
                    drawsSocket: false,
                    solidColor: solid(color, opacity: opacity)
                )
            case .link:
                let tier = edge.link?.tier ?? .legacy
                let color = edge.isDeparting ? Lagoon.textTertiary : Lagoon.linkColor(tier)
                let opacity = (edge.isDeparting ? 0.45 : 0.95) * dimFactor
                return GraphEdgeStroke(
                    id: edge.id,
                    path: edge.curve.path,
                    end: edge.curve.end,
                    color: color,
                    width: edge.isDeparting ? 1.25 : Lagoon.linkWidth(tier),
                    dash: edge.isDashed ? [4, 4] : [],
                    glows: !edge.isDeparting && Lagoon.linkGlows(tier),
                    opacity: opacity,
                    drawsSocket: true,
                    solidColor: solid(color, opacity: opacity)
                )
            }
        }
    }

    /// `color` at `opacity` over the map's black background, as one opaque
    /// colour.
    static func solid(_ color: Color, opacity: Double) -> Color {
        opacity >= 1 ? color : color.mix(with: Lagoon.background, by: 1 - opacity, in: .device)
    }

    static func pulseTracks(for layout: GraphLayout, dimmed: Set<String>) -> [GraphPulseTrack] {
        layout.edges.compactMap { edge in
            guard edge.isActive, !edge.isDeparting, let link = edge.link, !dimmed.contains(edge.toID) else {
                return nil
            }
            let tier = link.tier
            let isTrunk = edge.kind == .trunk
            return GraphPulseTrack(
                id: edge.id,
                curve: edge.curve,
                color: isTrunk ? Lagoon.accent : Lagoon.accentGlow,
                radius: isTrunk ? 1.6 : 2 + CGFloat(tier.rawValue) * 0.18,
                period: period(for: tier),
                phase: phase(for: edge.id),
                dots: tier >= .gbps20 && !isTrunk ? 2 : 1
            )
        }
    }

    /// About 1.6 s per trip at 10 Gb/s; faster links pulse faster.
    static func period(for tier: SpeedTier) -> Double {
        switch tier {
        case .legacy: return 3.0
        case .gbps5: return 2.1
        case .gbps10: return 1.6
        case .gbps20: return 1.3
        case .gbps40: return 1.05
        case .gbps80: return 0.85
        }
    }

    /// A stable 0…1 offset from the edge ID (FNV-1a), so the pattern does not
    /// change between launches.
    static func phase(for id: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in id.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Double(hash % 1000) / 1000
    }
}

/// The links, drawn once per layout change.
///
/// Links that run together (several cables leaving one port or hub) must
/// look like one link, not a brighter one. So every glow is drawn into one
/// shared layer that is blurred and faded as a whole, and the strokes are
/// solid colours pre-blended with the background instead of translucent
/// ones, so overlapping strokes do not add up.
struct GraphLinksLayer: View {
    /// Strokes already in view points (`GraphEdgeStroke.viewed(through:)`).
    var strokes: [GraphEdgeStroke]
    /// The zoom, for the glow's blur.
    var scale: CGFloat = 1

    var body: some View {
        Canvas { context, _ in
            // Glows first, one layer per fade level (normal and dimmed).
            let glowing = strokes.filter(\.glows)
            for opacity in Set(glowing.map(\.opacity)).sorted() {
                var glow = context
                glow.opacity = 0.55 * opacity
                glow.addFilter(.blur(radius: 5 * scale))
                glow.drawLayer { layer in
                    for stroke in glowing where stroke.opacity == opacity {
                        layer.stroke(
                            stroke.path,
                            with: .color(stroke.color),
                            style: StrokeStyle(lineWidth: stroke.width * 2.8, lineCap: .round)
                        )
                    }
                }
            }
            // Dimmed and slower links underneath, faster ones on top.
            let ordered = strokes.sorted { ($0.opacity, $0.width) < ($1.opacity, $1.width) }
            for stroke in ordered {
                let color = stroke.solidColor
                context.stroke(
                    stroke.path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round, dash: stroke.dash)
                )
                if stroke.drawsSocket {
                    context.fill(stroke.socketPath, with: .color(color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The hovered and the selected links, drawn over the others: a soft accent
/// halo and a brighter, slightly wider stroke. The selected link also gets
/// an accent outline, so it stays marked while the pointer is elsewhere.
struct GraphLinkHighlightLayer: View {
    /// Only the strokes to highlight, in view points.
    var strokes: [GraphEdgeStroke]
    var selected: Set<String>
    var hovered: String?
    /// The zoom, for the halo and outline widths.
    var scale: CGFloat = 1

    var body: some View {
        let accent = Lagoon.accentGlow
        let background = Lagoon.background
        Canvas { context, _ in
            for stroke in strokes {
                let isSelected = selected.contains(stroke.id)
                let isHovered = stroke.id == hovered
                guard isSelected || isHovered else { continue }

                var halo = context
                halo.opacity = isSelected ? 0.5 : 0.32
                halo.addFilter(.blur(radius: 4 * scale))
                halo.stroke(stroke.path, with: .color(accent),
                            style: StrokeStyle(lineWidth: stroke.width + 8 * scale, lineCap: .round))

                if isSelected {
                    context.stroke(stroke.path, with: .color(accent),
                                   style: StrokeStyle(lineWidth: stroke.width + 3.5 * scale, lineCap: .round, lineJoin: .round))
                }
                let core = stroke.color.mix(with: .white, by: isHovered ? 0.4 : 0.2, in: .device)
                context.stroke(
                    stroke.path,
                    with: .color(isSelected ? background : core),
                    style: StrokeStyle(lineWidth: stroke.width + (isSelected ? 1 : 1.5) * scale, lineCap: .round, lineJoin: .round)
                )
                if isSelected {
                    context.stroke(stroke.path, with: .color(core),
                                   style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round))
                }
                if stroke.drawsSocket {
                    context.fill(stroke.socketPath, with: .color(isSelected ? accent : core))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Small bright dots travelling along active links.
///
/// The timeline exists only while there is something to move: with
/// animation off (setting, Reduce Motion, window hidden or covered) or no
/// active link, nothing redraws.
struct GraphPulseLayer: View {
    /// Tracks in layout coordinates, drawn through `camera`.
    var tracks: [GraphPulseTrack]
    var camera: GraphCamera
    var animate: Bool

    var body: some View {
        if animate && !tracks.isEmpty {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                pulses(at: timeline.date.timeIntervalSinceReferenceDate)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func pulses(at time: TimeInterval) -> some View {
        Canvas { context, _ in
            for track in tracks {
                for index in 0..<max(track.dots, 1) {
                    let raw = time / track.period + track.phase + Double(index) / Double(max(track.dots, 1))
                    let progress = raw - raw.rounded(.down)
                    let point = camera.screenPoint(track.curve.point(at: CGFloat(progress)))
                    // Fade in as a dot leaves its start and out as it arrives.
                    let fade = sin(progress * .pi)
                    let radius = track.radius * camera.scale
                    let halo = radius * 3.4
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)),
                        with: .radialGradient(
                            Gradient(colors: [track.color.opacity(0.5 * fade), track.color.opacity(0)]),
                            center: point,
                            startRadius: 0,
                            endRadius: halo
                        )
                    )
                    let core = radius
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)),
                        with: .color(track.color.opacity(0.95 * fade))
                    )
                }
            }
        }
    }
}

/// Speed chips at the middle of each link.
struct GraphChipsLayer: View {
    /// Edges whose chips are on screen.
    var edges: [GraphEdge]
    var dimmed: Set<String>
    /// Chips never grow wider than the gap between columns.
    var maxChipWidth: CGFloat = 84
    var camera: GraphCamera

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(edges.filter { $0.chipPoint != nil && $0.link != nil }) { edge in
                if let link = edge.link, let point = edge.chipPoint {
                    SpeedChip(link: link)
                        .background(Capsule().fill(Lagoon.background))
                        .frame(maxWidth: maxChipWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .scaleEffect(camera.scale)
                        .position(camera.screenPoint(point))
                        .opacity(dimmed.contains(edge.toID) ? 0.25 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A faint dot grid and a soft glow behind the host, so the canvas reads as a
/// map. The grid is fixed to the layout, so it moves and zooms with the
/// graph, and only its visible dots are drawn.
struct GraphBackdrop: View {
    /// The host card, in layout coordinates.
    var hostFrame: CGRect?
    var camera: GraphCamera

    var body: some View {
        let dotColor = Lagoon.accent.opacity(0.07)
        let glowColor = Lagoon.accent
        Canvas { context, size in
            // 24 layout points apart; zoomed far out, every second (fourth…)
            // dot, so the grid never gets denser than 12 points on screen.
            var spacing: CGFloat = 24
            while spacing * camera.scale < 12 { spacing *= 2 }
            let visible = camera.visibleLayoutRect(in: size)
            let dot = 0.8 * camera.scale
            var dots = Path()
            var y = (visible.minY / spacing).rounded(.down) * spacing + spacing / 2
            while y < visible.maxY + spacing {
                var x = (visible.minX / spacing).rounded(.down) * spacing + spacing / 2
                while x < visible.maxX + spacing {
                    let point = camera.screenPoint(CGPoint(x: x, y: y))
                    dots.addEllipse(in: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .color(dotColor))

            if let hostFrame {
                let center = camera.screenPoint(CGPoint(x: hostFrame.midX, y: hostFrame.midY))
                let radius = max(hostFrame.width, hostFrame.height) * 1.1 * camera.scale
                guard radius > 0 else { return }
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .radialGradient(
                        Gradient(colors: [glowColor.opacity(0.10), glowColor.opacity(0)]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
