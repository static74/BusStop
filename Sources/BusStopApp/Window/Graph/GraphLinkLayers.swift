import BusStopCore
import SwiftUI

// Layers drawn behind the graph's nodes: a dotted backdrop, the links (static
// Canvas, redrawn only when the layout changes), the travelling pulses
// (TimelineView + Canvas) and the speed chips.

nonisolated extension GraphCurve {
    var path: Path {
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }
}

/// How one edge is painted, resolved from the Lagoon tokens.
struct GraphEdgeStroke: Identifiable {
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
                return GraphEdgeStroke(
                    id: edge.id,
                    path: edge.curve.path,
                    end: edge.curve.end,
                    color: color,
                    width: edge.isActive ? 1.4 : 1,
                    dash: edge.isDashed ? [3, 4] : [],
                    glows: false,
                    opacity: (edge.isActive ? 0.42 : 0.7) * dimFactor,
                    drawsSocket: false
                )
            case .link:
                let tier = edge.link?.tier ?? .legacy
                let color = edge.isDeparting ? Lagoon.textTertiary : Lagoon.linkColor(tier)
                return GraphEdgeStroke(
                    id: edge.id,
                    path: edge.curve.path,
                    end: edge.curve.end,
                    color: color,
                    width: edge.isDeparting ? 1.25 : Lagoon.linkWidth(tier),
                    dash: edge.isDashed ? [4, 4] : [],
                    glows: !edge.isDeparting && Lagoon.linkGlows(tier),
                    opacity: (edge.isDeparting ? 0.45 : 0.95) * dimFactor,
                    drawsSocket: true
                )
            }
        }
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
struct GraphLinksLayer: View {
    var strokes: [GraphEdgeStroke]

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes {
                if stroke.glows {
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: 5))
                        layer.stroke(
                            stroke.path,
                            with: .color(stroke.color.opacity(0.55 * stroke.opacity)),
                            style: StrokeStyle(lineWidth: stroke.width * 2.8, lineCap: .round)
                        )
                    }
                }
                context.stroke(
                    stroke.path,
                    with: .color(stroke.color.opacity(stroke.opacity)),
                    style: StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round, dash: stroke.dash)
                )
                if stroke.drawsSocket {
                    let radius = max(2.2, stroke.width * 0.95)
                    let rect = CGRect(x: stroke.end.x - radius, y: stroke.end.y - radius,
                                      width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(stroke.color.opacity(stroke.opacity)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Small bright dots travelling along active links.
struct GraphPulseLayer: View {
    var tracks: [GraphPulseTrack]
    var animate: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animate)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, _ in
                guard animate else { return }
                for track in tracks {
                    for index in 0..<max(track.dots, 1) {
                        let raw = time / track.period + track.phase + Double(index) / Double(max(track.dots, 1))
                        let progress = raw - raw.rounded(.down)
                        let point = track.curve.point(at: CGFloat(progress))
                        // Fade in as a dot leaves its start and out as it arrives.
                        let fade = sin(progress * .pi)
                        let halo = track.radius * 3.4
                        context.fill(
                            Path(ellipseIn: CGRect(x: point.x - halo, y: point.y - halo, width: halo * 2, height: halo * 2)),
                            with: .radialGradient(
                                Gradient(colors: [track.color.opacity(0.5 * fade), track.color.opacity(0)]),
                                center: point,
                                startRadius: 0,
                                endRadius: halo
                            )
                        )
                        let core = track.radius
                        context.fill(
                            Path(ellipseIn: CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)),
                            with: .color(track.color.opacity(0.95 * fade))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Speed chips at the middle of each link.
struct GraphChipsLayer: View {
    var edges: [GraphEdge]
    var dimmed: Set<String>

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(edges.filter { $0.chipPoint != nil && $0.link != nil }) { edge in
                if let link = edge.link, let point = edge.chipPoint {
                    SpeedChip(link: link)
                        .background(Capsule().fill(Lagoon.background))
                        .fixedSize()
                        .position(point)
                        .opacity(dimmed.contains(edge.toID) ? 0.25 : 1)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A faint dot grid and a soft glow behind the host, so the canvas reads as a map.
struct GraphBackdrop: View {
    var hostFrame: CGRect?

    var body: some View {
        let dotColor = Lagoon.accent.opacity(0.07)
        let glowColor = Lagoon.accent
        Canvas { context, size in
            let spacing: CGFloat = 24
            var dots = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                    x += spacing
                }
                y += spacing
            }
            context.fill(dots, with: .color(dotColor))

            if let hostFrame {
                let center = CGPoint(x: hostFrame.midX, y: hostFrame.midY)
                let radius = max(hostFrame.width, hostFrame.height) * 1.1
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
