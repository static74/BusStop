import CoreGraphics

// Read-only geometry on a finished `GraphLayout` for clicking links: which
// edge lies under the pointer, and which edges lead to a selected node. The
// layout itself is never changed here.

nonisolated extension GraphCurve {
    /// Points along the curve, `segments + 1` of them, start and end included.
    func polyline(segments: Int = 48) -> [CGPoint] {
        let count = max(segments, 1)
        return (0...count).map { point(at: CGFloat($0) / CGFloat(count)) }
    }

    /// A rectangle that contains the whole curve: a cubic Bézier never leaves
    /// the bounds of its control points.
    var bounds: CGRect {
        let xs = [start.x, control1.x, control2.x, end.x]
        let ys = [start.y, control1.y, control2.y, end.y]
        let minX = xs.min() ?? 0, minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }

    /// Distance from `point` to the curve, measured on a 48-segment polyline.
    func distance(to point: CGPoint) -> CGFloat {
        let points = polyline()
        var best = CGFloat.infinity
        for (a, b) in zip(points, points.dropFirst()) {
            best = min(best, Self.distance(from: point, toSegment: a, b))
        }
        return best
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        var t: CGFloat = 0
        if lengthSquared > 0 {
            t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
        }
        let x = a.x + t * dx - p.x, y = a.y + t * dy - p.y
        return (x * x + y * y).squareRoot()
    }
}

nonisolated extension GraphLayout {
    /// The selection tag of the node `edge` leads to, which names the link
    /// (`SelectionTag.link`). Nil when the link cannot be selected: the trunk
    /// to the Other group and links to departing devices.
    func childTag(of edge: GraphEdge) -> String? {
        node(id: edge.toID)?.tag
    }

    /// The selectable edge nearest to `point` (layout coordinates), or nil
    /// when none is within `tolerance`.
    func edge(near point: CGPoint, tolerance: CGFloat) -> GraphEdge? {
        let tags = Dictionary(nodes.map { ($0.id, $0.tag) }, uniquingKeysWith: { first, _ in first })
        var best: (edge: GraphEdge, distance: CGFloat)?
        for edge in edges {
            guard let tag = tags[edge.toID] ?? nil, !tag.isEmpty,
                  edge.curve.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
            let distance = edge.curve.distance(to: point)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (edge, distance)
            }
        }
        return best?.edge
    }

    /// IDs of the edges that lead to the node tagged `childTag`. Usually one;
    /// more only when the same device is drawn twice.
    func edgeIDs(leadingTo childTag: String) -> Set<String> {
        let targets = Set(nodes.filter { $0.tag == childTag }.map(\.id))
        return Set(edges.filter { targets.contains($0.toID) }.map(\.id))
    }
}
