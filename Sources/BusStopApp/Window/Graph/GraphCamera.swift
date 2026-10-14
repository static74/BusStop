import CoreGraphics

/// Where the map looks: a layout point `p` is drawn at `p × scale + offset`
/// in the map view.
///
/// The map owns this instead of a scroll view, so the graph is drawn at
/// screen resolution at any zoom, only what is visible is drawn, and the map
/// pans freely like a web map (see `docs/decisions.md`).
nonisolated struct GraphCamera: Equatable {
    var scale: CGFloat
    var offset: CGPoint

    /// How much of the graph, in points, always stays on screen.
    static let keepVisible: CGFloat = 80

    var transform: CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset.x, ty: offset.y)
    }

    func screenPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y)
    }

    func layoutPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / scale, y: (point.y - offset.y) / scale)
    }

    /// The layout rectangle a view of `size` shows.
    func visibleLayoutRect(in size: CGSize) -> CGRect {
        CGRect(origin: layoutPoint(.zero), size: CGSize(width: size.width / scale, height: size.height / scale))
    }

    func panned(by translation: CGSize) -> GraphCamera {
        GraphCamera(scale: scale, offset: CGPoint(x: offset.x + translation.width, y: offset.y + translation.height))
    }

    /// Zoomed to `newScale`, keeping the layout point under `location` (in
    /// the view) where it is.
    func zoomed(to newScale: CGFloat, at location: CGPoint) -> GraphCamera {
        let anchor = layoutPoint(location)
        return GraphCamera(scale: newScale, offset: CGPoint(x: location.x - anchor.x * newScale,
                                                            y: location.y - anchor.y * newScale))
    }

    /// Moved so the middle of `rect` (layout coordinates) is in the middle of
    /// a view of `size`.
    func centering(_ rect: CGRect, in size: CGSize) -> GraphCamera {
        GraphCamera(scale: scale, offset: CGPoint(x: size.width / 2 - rect.midX * scale,
                                                  y: size.height / 2 - rect.midY * scale))
    }

    /// Kept so at least `keepVisible` points of a graph of `layout` size stay
    /// in a view of `size`: the map cannot be dragged away and lost.
    func clamped(layout: CGSize, viewport size: CGSize) -> GraphCamera {
        func clamp(_ value: CGFloat, length: CGFloat, view: CGFloat) -> CGFloat {
            let keep = min(Self.keepVisible, length / 2, view / 2)
            return min(max(value, keep - length), view - keep)
        }
        return GraphCamera(scale: scale, offset: CGPoint(
            x: clamp(offset.x, length: layout.width * scale, view: size.width),
            y: clamp(offset.y, length: layout.height * scale, view: size.height)))
    }

    /// The fitting camera at `scale`: the graph in the middle of the view, or
    /// against its top-left corner along an axis where it does not fit.
    static func fit(layout: CGSize, viewport size: CGSize, scale: CGFloat) -> GraphCamera {
        GraphCamera(scale: scale, offset: CGPoint(x: max(0, ((size.width - layout.width * scale) / 2).rounded(.down)),
                                                  y: max(0, ((size.height - layout.height * scale) / 2).rounded(.down))))
    }
}
