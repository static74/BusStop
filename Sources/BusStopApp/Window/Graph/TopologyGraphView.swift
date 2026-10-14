import BusStopCore
import SwiftUI

/// The topology graph: the Mac, its ports and every device chain, drawn as a
/// map with speed-coloured links and travelling pulses. Overview's Graph mode
/// and the per-port pages use it.
struct TopologyGraphView: View {
    var store: PortStore
    /// Ports to draw, top to bottom.
    var ports: [PhysicalPort]
    /// Also draw devices and displays that are not tied to a port.
    var includeOther: Bool
    var searchText: String
    /// The zoom the user picked; nil fits the graph to the window.
    @Binding var userZoom: Double?
    /// False while the window is closed, minimised or covered: pulses pause.
    var isWindowVisible: Bool
    /// A node to scroll into view; cleared once handled.
    @Binding var scrollRequest: TopologyScrollRequest?

    @GestureState private var pinch: CGFloat = 1
    @State private var position = ScrollPosition()
    /// Scroll geometry for panning and pointer-anchored zoom. A plain
    /// reference, so scrolling does not re-run `body`.
    @State private var tracker = GraphScrollTracker()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lagoonTextScale) private var textScale

    /// Zoom chosen with the buttons, the scroll wheel or a pinch.
    static let zoomRange: ClosedRange<Double> = 0.25...2.0
    /// Fitting the window never goes below this, so text stays readable; a
    /// larger graph scrolls instead.
    static let minimumFitZoom = 0.5

    var body: some View {
        let input = graphInput
        // Cards grow with the Text Size setting, like the text inside them.
        let layout = GraphLayout.make(input, metrics: GraphMetrics.standard.scaled(by: textScale))
        if Self.isOnlyHost(input) {
            PortListEmptyView(state: PortListEmptyState.resolve(searchText: "", store: store), store: store)
                .onChange(of: scrollRequest, initial: true) { _, request in
                    // Nothing to scroll to; do not leave the request for a later graph.
                    if request != nil { scrollRequest = nil }
                }
        } else {
            graph(layout)
        }
    }

    private func graph(_ layout: GraphLayout) -> some View {
        let dimmed = dimmedNodeIDs(in: layout)
        let animate = store.settings.animateLinks && !reduceMotion && isWindowVisible
        return GeometryReader { proxy in
            let base = userZoom ?? Self.fitZoom(content: layout.size, viewport: proxy.size)
            let viewport = GraphViewport(layout: layout.size, viewport: proxy.size,
                                         scale: Self.clamp(base * Double(pinch)))
            ScrollView([.horizontal, .vertical]) {
                GraphCanvas(
                    layout: layout,
                    origin: viewport.origin,
                    snapshot: store.snapshot,
                    selectedTag: SelectionTag.string(for: store.selection),
                    dimmed: dimmed,
                    animate: animate,
                    onSelect: select,
                    // About 6 points on screen at any zoom.
                    hitTolerance: 6 / viewport.scale,
                    onSelectLink: selectLink,
                    onPan: pan,
                    onPanEnded: { tracker.panStart = nil }
                )
                .frame(width: viewport.canvasSize.width, height: viewport.canvasSize.height, alignment: .topLeading)
                .scaleEffect(viewport.scale, anchor: .topLeading)
                .frame(width: viewport.contentSize.width, height: viewport.contentSize.height, alignment: .topLeading)
            }
            .scrollPosition($position)
            .scrollIndicators(.never)
            // While the graph fits itself, keep it in the middle of the
            // window as the window or the graph changes size.
            .onChange(of: viewport, initial: true) { goHome(viewport) }
            .onChange(of: userZoom == nil) { goHome(viewport) }
            .onScrollGeometryChange(for: GraphScrollMetrics.self) { geometry in
                GraphScrollMetrics(geometry)
            } action: { old, new in
                tracker.metrics = new
                // A zoom changes the content size; its anchored offset can
                // only be applied once the content has that size.
                if old.contentSize != new.contentSize, let pending = tracker.pendingOffset {
                    tracker.pendingOffset = nil
                    position.scrollTo(point: tracker.clamped(pending))
                }
            }
            .background {
                GraphScrollWheelZoom { factor, location in
                    zoom(by: factor, at: location, layout: layout, size: proxy.size,
                         fitZoom: Self.fitZoom(content: layout.size, viewport: proxy.size))
                }
            }
            .overlay(alignment: .bottom) {
                let fitZoom = Self.fitZoom(content: layout.size, viewport: proxy.size)
                controls(zoom: Double(viewport.scale)) { target in
                    // Buttons zoom around the middle of the window.
                    zoom(by: target / Self.clamp(userZoom ?? fitZoom),
                         at: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2),
                         layout: layout, size: proxy.size, fitZoom: fitZoom)
                } onFit: {
                    // Already fitting, perhaps dragged away: go back home.
                    if userZoom == nil { goHome(viewport) } else { userZoom = nil }
                }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in userZoom = Self.clamp(base * Double(value.magnification)) }
            )
            .onChange(of: scrollRequest, initial: true) { _, request in
                guard let request else { return }
                scrollRequest = nil
                scroll(to: request, layout: layout, viewport: viewport, size: proxy.size)
            }
        }
    }

    private func controls(zoom: Double, onZoom: @escaping (Double) -> Void,
                          onFit: @escaping () -> Void) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                GraphSpeedLegend()
                Color.clear.frame(width: 0, height: 0)
            }
            Spacer(minLength: 0)
            GraphZoomControl(
                zoom: zoom,
                isFitting: userZoom == nil,
                onZoom: onZoom,
                onFit: onFit
            )
        }
        .padding(16)
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }

    /// The automatic zoom: the graph fits across the window, never above
    /// 100 % or below `minimumFitZoom`. Height counts only down to 75 %, so a
    /// tall tree scrolls vertically instead of shrinking to unreadable text.
    static func fitZoom(content: CGSize, viewport: CGSize) -> Double {
        guard content.width > 0, content.height > 0, viewport.width > 0, viewport.height > 0 else { return 1 }
        let byWidth = Double(viewport.width / content.width)
        let byHeight = Double(viewport.height / content.height)
        let fit = min(1, byWidth, max(byHeight, 0.75))
        return clamp(max(minimumFitZoom, (fit * 20).rounded(.down) / 20))
    }

    /// True when the graph would show the Mac alone: no ports to draw and
    /// nothing in the Other group.
    private static func isOnlyHost(_ input: GraphInput) -> Bool {
        input.ports.isEmpty && input.otherDevices.isEmpty && input.otherDisplays.isEmpty
            && input.departingOther.isEmpty
    }

    /// Scrolls so the requested node (or the middle of a link) sits in the
    /// middle of the window.
    private func scroll(to request: TopologyScrollRequest, layout: GraphLayout, viewport: GraphViewport, size: CGSize) {
        guard let tag = request.tag else { return }
        let rect: CGRect
        if let child = SelectionTag.linkTarget(of: tag) {
            let ids = layout.edgeIDs(leadingTo: child)
            guard let edge = layout.edges.first(where: { ids.contains($0.id) }) else { return }
            rect = CGRect(origin: edge.curve.midpoint, size: .zero)
        } else {
            guard let node = layout.nodes.first(where: { $0.tag == tag }) else { return }
            rect = node.frame
        }
        let target = viewport.scrollOffset(centering: rect, in: size)
        tracker.pendingOffset = nil
        position.scrollTo(point: target)
        // Again once the scroll view has laid out content that just appeared.
        Task { @MainActor in
            withAnimation(.snappy) { position.scrollTo(point: target) }
        }
    }

    /// Scrolls a fitting graph to its home offset, once the scroll view has
    /// the content size that offset belongs to.
    private func goHome(_ viewport: GraphViewport) {
        guard userZoom == nil, pinch == 1 else { return }
        let metrics = tracker.metrics
        let home = viewport.homeOffset
        if abs(metrics.contentSize.width - viewport.contentSize.width) < 1,
           abs(metrics.contentSize.height - viewport.contentSize.height) < 1 {
            tracker.pendingOffset = nil
            position.scrollTo(point: home)
        } else {
            tracker.pendingOffset = home
        }
    }

    /// Drag to pan: the content follows the pointer one to one, within the
    /// content's bounds. `start` (window coordinates) tells one drag from
    /// the next.
    private func pan(start: CGPoint, translation: CGSize) {
        if tracker.panStart?.location != start {
            tracker.panStart = GraphPanStart(location: start, offset: tracker.metrics.offset)
        }
        guard let origin = tracker.panStart?.offset else { return }
        tracker.pendingOffset = nil
        position.scrollTo(point: tracker.clamped(CGPoint(x: origin.x - translation.width,
                                                         y: origin.y - translation.height)))
    }

    /// Scroll-wheel zoom by `factor`, keeping the point under the pointer
    /// (`location`, in the scroll view) where it is. Ends Fit mode.
    private func zoom(by factor: Double, at location: CGPoint, layout: GraphLayout, size: CGSize, fitZoom: Double) {
        // `userZoom` and `pendingOffset` already hold the previous step when
        // several wheel events arrive before the graph is redrawn.
        let current = Self.clamp(userZoom ?? fitZoom)
        let zoom = Self.clamp(current * factor)
        guard abs(zoom - current) > 0.0001 else { return }
        let before = GraphViewport(layout: layout.size, viewport: size, scale: current)
        let after = GraphViewport(layout: layout.size, viewport: size, scale: zoom)
        let offset = tracker.pendingOffset ?? tracker.metrics.offset
        let anchor = before.layoutPoint(atContent: CGPoint(x: offset.x + location.x, y: offset.y + location.y))
        let target = after.scrollOffset(placing: anchor, at: location)
        userZoom = zoom
        if after.contentSize == before.contentSize {
            tracker.pendingOffset = nil
            position.scrollTo(point: tracker.clamped(target))
        } else {
            tracker.pendingOffset = target
        }
    }

    private func select(_ node: GraphNode) {
        guard let tag = node.tag, let selection = SelectionTag.selection(for: tag) else { return }
        store.selection = selection
    }

    /// Selects the link that leads to the node tagged `childTag`.
    private func selectLink(_ childTag: String) {
        guard let selection = SelectionTag.selection(for: SelectionTag.link(childTag)) else { return }
        store.selection = selection
    }

    /// The layout input: the given ports plus ghosts for departing devices,
    /// displays missing from device trees and (optionally) the Other group.
    private var graphInput: GraphInput {
        let snapshot = store.snapshot
        let portKeys = Set(ports.map(\.key))

        var departingByPort: [PortKey: [DeviceNode]] = [:]
        var departingOther: [DeviceNode] = []
        for entry in store.departing {
            if let key = entry.portKey {
                if portKeys.contains(key) { departingByPort[key, default: []].append(entry.device) }
            } else if includeOther {
                departingOther.append(entry.device)
            }
        }

        return GraphInput(
            ports: ports,
            otherDevices: includeOther ? snapshot.otherDevices : [],
            otherDisplays: includeOther ? TopologyExtras.otherDisplays(in: snapshot) : [],
            portDisplays: TopologyExtras.portDisplays(in: snapshot, ports: ports),
            departingByPort: departingByPort,
            departingOther: departingOther
        )
    }

    /// Nodes that do not match the search (nor lead to a match) are dimmed.
    private func dimmedNodeIDs(in layout: GraphLayout) -> Set<String> {
        let query = TopologySearch.normalized(searchText)
        guard !query.isEmpty else { return [] }
        let matchingPorts = Set(ports.filter { TopologySearch.port($0, matches: query) }.map(\.key))

        var lit: Set<String> = [GraphLayout.hostID]
        for node in layout.nodes {
            let portMatches = node.portKey.map { matchingPorts.contains($0) } ?? false
            switch node.content {
            case .host:
                break
            case .port:
                if portMatches { lit.insert(node.id) }
            case .otherGroup:
                break
            case .device(let device, _):
                if portMatches || TopologySearch.device(device, matches: query) { lit.insert(node.id) }
            case .display(let display):
                if portMatches || TopologySearch.display(display, matches: query) { lit.insert(node.id) }
            }
        }

        // Keep the path from the host to every match lit.
        var parents: [String: String] = [:]
        for node in layout.nodes {
            if let parent = node.parentID { parents[node.id] = parent }
        }
        for id in Array(lit) {
            var current = parents[id]
            while let parent = current {
                lit.insert(parent)
                current = parents[parent]
            }
        }
        return Set(layout.nodes.map(\.id)).subtracting(lit)
    }
}

/// Where the graph sits inside the scroll view at one zoom level.
///
/// The canvas is at least as large as the window at that zoom, so the dot
/// grid and the glow fill the whole viewport, and a graph smaller than the
/// window sits in its middle. Half a window of margin on every side lets
/// the map be dragged in any direction, even when it fits.
nonisolated struct GraphViewport: Equatable {
    /// Canvas size at 100 % zoom.
    var canvasSize: CGSize
    /// Offset of the layout inside the canvas, at 100 % zoom.
    var origin: CGPoint
    var scale: CGFloat
    /// The margin around the graph's area, at 100 % zoom.
    var margin: CGSize

    init(layout: CGSize, viewport: CGSize, scale: Double) {
        let scale = CGFloat(scale)
        let area = CGSize(width: max(layout.width, (viewport.width / scale).rounded(.up)),
                          height: max(layout.height, (viewport.height / scale).rounded(.up)))
        margin = CGSize(width: (viewport.width / scale / 2).rounded(.up),
                        height: (viewport.height / scale / 2).rounded(.up))
        canvasSize = CGSize(width: area.width + 2 * margin.width, height: area.height + 2 * margin.height)
        origin = CGPoint(x: margin.width + ((area.width - layout.width) / 2).rounded(.down),
                         y: margin.height + ((area.height - layout.height) / 2).rounded(.down))
        self.scale = scale
    }

    /// The scroll offset that shows the graph's area from its top-left
    /// corner, as an unpadded canvas did at offset zero.
    var homeOffset: CGPoint {
        CGPoint(x: margin.width * scale, y: margin.height * scale)
    }

    /// Size of the scroll view's content.
    var contentSize: CGSize {
        CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
    }

    /// The scroll offset that puts `rect` (layout coordinates) in the middle
    /// of a viewport of `size`, kept within the content.
    func scrollOffset(centering rect: CGRect, in size: CGSize) -> CGPoint {
        let target = scrollOffset(placing: CGPoint(x: rect.midX, y: rect.midY),
                                  at: CGPoint(x: size.width / 2, y: size.height / 2))
        let maxX = max(0, contentSize.width - size.width)
        let maxY = max(0, contentSize.height - size.height)
        return CGPoint(x: min(max(0, target.x), maxX), y: min(max(0, target.y), maxY))
    }

    /// The scroll offset that puts `point` (layout coordinates) at
    /// `location` in the viewport. Not kept within the content.
    func scrollOffset(placing point: CGPoint, at location: CGPoint) -> CGPoint {
        CGPoint(x: (origin.x + point.x) * scale - location.x, y: (origin.y + point.y) * scale - location.y)
    }

    /// The layout point at `point` in the scroll view's (zoomed) content.
    func layoutPoint(atContent point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / scale - origin.x, y: point.y / scale - origin.y)
    }
}

/// The parts of the scroll view's geometry that panning and zooming need.
nonisolated struct GraphScrollMetrics: Equatable, Sendable {
    /// The content point at the scroll view's top-left corner.
    var offset: CGPoint = .zero
    var contentSize: CGSize = .zero
    var containerSize: CGSize = .zero
    var insets = EdgeInsets()

    init() {}

    init(_ geometry: ScrollGeometry) {
        offset = geometry.contentOffset
        contentSize = geometry.contentSize
        containerSize = geometry.containerSize
        insets = geometry.contentInsets
    }
}

/// Where a pan started: the pointer, in window coordinates, and the scroll
/// offset at that moment.
nonisolated struct GraphPanStart: Equatable {
    var location: CGPoint
    var offset: CGPoint
}

/// Scroll state the graph reads while panning and zooming. Not observed:
/// updating it on every scroll step must not redraw the graph.
final class GraphScrollTracker {
    var metrics = GraphScrollMetrics()
    /// The scroll offset a zoom waits to apply until the content has its
    /// new size.
    var pendingOffset: CGPoint?
    var panStart: GraphPanStart?

    /// `point` kept within the offsets the scroll view can show.
    func clamped(_ point: CGPoint) -> CGPoint {
        let minX = -metrics.insets.leading
        let minY = -metrics.insets.top
        let maxX = max(minX, metrics.contentSize.width + metrics.insets.trailing - metrics.containerSize.width)
        let maxY = max(minY, metrics.contentSize.height + metrics.insets.bottom - metrics.containerSize.height)
        return CGPoint(x: min(max(point.x, minX), maxX), y: min(max(point.y, minY), maxY))
    }
}

/// The graph content at 100 % zoom: backdrop, links, pulses, chips and nodes.
/// The backdrop fills the canvas; everything else is drawn at `origin`.
///
/// Dragging anywhere pans the map. Under the nodes, one hit layer covers the
/// canvas: it finds the link nearest the pointer, highlights it on hover and
/// selects it on click. Nodes sit above it and keep their own clicks.
struct GraphCanvas: View {
    var layout: GraphLayout
    var origin: CGPoint = .zero
    var snapshot: HostSnapshot
    var selectedTag: String?
    var dimmed: Set<String>
    var animate: Bool
    var onSelect: (GraphNode) -> Void
    /// How close to a link, in canvas points, a click must land to select it.
    var hitTolerance: CGFloat = 6
    /// Called with the tag of the node a clicked link leads to.
    var onSelectLink: (String) -> Void = { _ in }
    /// Called while the canvas is dragged, with the drag's start and its
    /// translation, both in window points.
    var onPan: (CGPoint, CGSize) -> Void = { _, _ in }
    var onPanEnded: () -> Void = {}

    @State private var hoveredEdgeID: String?
    /// Set once a drag has moved far enough to count as a pan, so the click
    /// that ends it does not also select a node or a link.
    @State private var didPan = false
    @GestureState private var isPanning = false

    var body: some View {
        let strokes = GraphPaint.strokes(for: layout, dimmed: dimmed)
        let selectedLinks = SelectionTag.linkTarget(of: selectedTag).map { layout.edgeIDs(leadingTo: $0) } ?? []
        ZStack(alignment: .topLeading) {
            GraphBackdrop(hostFrame: layout.hostNode?.frame.offsetBy(dx: origin.x, dy: origin.y))
            hitLayer
            content(strokes: strokes, selectedLinks: selectedLinks)
                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                .offset(x: origin.x, y: origin.y)
        }
        // While panning, the closed hand shows over the nodes too.
        .pointerStyle(isPanning ? PointerStyle.grabActive : nil)
        .simultaneousGesture(panGesture)
        .onChange(of: isPanning) { _, panning in
            guard !panning else { return }
            onPanEnded()
            // Let the click that ended the pan go by first.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                didPan = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Topology map")
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .updating($isPanning) { _, state, _ in state = true }
            .onChanged { value in
                if !didPan, hypot(value.translation.width, value.translation.height) > 4 { didPan = true }
                onPan(value.startLocation, value.translation)
            }
    }

    /// Hover and click targets for the links, over the whole canvas.
    private var hitLayer: some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                var hovered: String?
                if case .active(let location) = phase {
                    hovered = edge(at: location)?.id
                }
                if hovered != hoveredEdgeID { hoveredEdgeID = hovered }
            }
            .onTapGesture { location in
                guard !didPan, let edge = edge(at: location), let tag = layout.childTag(of: edge) else { return }
                onSelectLink(tag)
            }
            .pointerStyle(hitLayerPointer)
            .accessibilityHidden(true)
    }

    /// An open hand over the map, a closed one while panning, a pointing
    /// hand over a link.
    private var hitLayerPointer: PointerStyle {
        if isPanning { return .grabActive }
        return hoveredEdgeID != nil ? .link : .grabIdle
    }

    /// The selectable link near `location` (canvas coordinates).
    private func edge(at location: CGPoint) -> GraphEdge? {
        layout.edge(near: CGPoint(x: location.x - origin.x, y: location.y - origin.y), tolerance: hitTolerance)
    }

    private func content(strokes: [GraphEdgeStroke], selectedLinks: Set<String>) -> some View {
        let highlighted = strokes.filter { selectedLinks.contains($0.id) || $0.id == hoveredEdgeID }
        return ZStack(alignment: .topLeading) {
            GraphLinksLayer(strokes: strokes)
            GraphLinkHighlightLayer(strokes: highlighted, selected: selectedLinks, hovered: hoveredEdgeID)
            GraphPulseLayer(tracks: GraphPaint.pulseTracks(for: layout, dimmed: dimmed), animate: animate)
            GraphChipsLayer(edges: layout.edges, dimmed: dimmed, maxChipWidth: layout.metrics.columnGap - 6)
            ForEach(layout.nodes) { node in
                GraphNodeView(
                    node: node,
                    snapshot: snapshot,
                    isSelected: node.tag != nil && node.tag == selectedTag,
                    isDimmed: dimmed.contains(node.id),
                    onSelect: { if !didPan { onSelect(node) } }
                )
                .frame(width: node.frame.width, height: node.frame.height)
                .position(x: node.frame.midX, y: node.frame.midY)
            }
        }
    }
}

/// Glass zoom cluster in the graph's corner: zoom out, actual size, zoom in,
/// and fit. Until the user zooms, the graph fits itself to the window; Fit
/// goes back to that.
struct GraphZoomControl: View {
    /// The zoom on screen, fitted or chosen.
    var zoom: Double
    /// True while the graph fits itself to the window.
    var isFitting: Bool
    /// The user picked a zoom.
    var onZoom: (Double) -> Void
    /// Back to fitting the window.
    var onFit: () -> Void

    var body: some View {
        let tint = AppSettings.shared.glassTint
        let percent = Int((zoom * 100).rounded())
        GlassEffectContainer {
            HStack(spacing: 2) {
                iconButton("minus.magnifyingglass", help: "Zoom Out") { step(-0.1) }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(zoom <= TopologyGraphView.zoomRange.lowerBound)
                Button {
                    onZoom(1)
                } label: {
                    Text("\(percent)%")
                        .lagoonFont(.caption, weight: .semibold, design: .rounded, monospacedDigits: true)
                        .foregroundStyle(Lagoon.textPrimary)
                        .frame(minWidth: 42, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("0", modifiers: .command)
                .help("Actual Size")
                .accessibilityLabel("Zoom \(percent) percent. Reset to actual size")
                iconButton("plus.magnifyingglass", help: "Zoom In") { step(0.1) }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(zoom >= TopologyGraphView.zoomRange.upperBound)
                Rectangle()
                    .fill(Lagoon.stroke)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 3)
                iconButton("arrow.up.left.and.down.right.magnifyingglass",
                           help: isFitting ? "Fitting the graph to the window" : "Zoom to Fit",
                           isOn: isFitting,
                           action: onFit)
                    .keyboardShortcut("9", modifiers: .command)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular.tint(Lagoon.accent.opacity(tint)).interactive(), in: .capsule)
        }
    }

    private func step(_ delta: Double) {
        onZoom(TopologyGraphView.clamp(((zoom + delta) * 10).rounded() / 10))
    }

    private func iconButton(_ systemName: String, help: String, isOn: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .lagoonFont(size: 12, weight: .semibold)
                .foregroundStyle(isOn ? Lagoon.accent : Lagoon.textPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// Key for the link colours: one swatch per speed tier.
struct GraphSpeedLegend: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 12) {
            ForEach(SpeedTier.allCases, id: \.self) { tier in
                HStack(spacing: 5) {
                    Capsule()
                        .fill(Lagoon.linkColor(tier))
                        .frame(width: 16, height: Lagoon.linkWidth(tier))
                        .shadow(color: Lagoon.linkGlows(tier) ? Lagoon.linkColor(tier).opacity(0.7) : .clear, radius: 3)
                    Text(Self.title(tier))
                        .lagoonFont(.caption2, weight: .medium, monospacedDigits: true)
                        .foregroundStyle(Lagoon.textSecondary)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Lagoon.surface.opacity(0.94)))
        .overlay(Capsule().strokeBorder(WindowContrast.stroke(contrast), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Link colours: dim for USB 2, brighter and thicker for faster links, glowing at 40 gigabits per second and above")
    }

    static func title(_ tier: SpeedTier) -> String {
        switch tier {
        case .legacy: return "USB 2"
        case .gbps5: return "5 Gb/s"
        case .gbps10: return "10 Gb/s"
        case .gbps20: return "20 Gb/s"
        case .gbps40: return "40 Gb/s"
        case .gbps80: return "80+ Gb/s"
        }
    }
}
