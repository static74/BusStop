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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lagoonTextScale) private var textScale

    static let zoomRange: ClosedRange<Double> = 0.5...1.5

    var body: some View {
        let input = graphInput
        // Cards grow with the Text Size setting, like the text inside them.
        let layout = GraphLayout.make(input, metrics: GraphMetrics.standard.scaled(by: textScale))
        if Self.isOnlyHost(input) {
            PortListEmptyView(state: PortListEmptyState.resolve(searchText: "", store: store), store: store)
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
                    onSelect: select
                )
                .frame(width: viewport.canvasSize.width, height: viewport.canvasSize.height, alignment: .topLeading)
                .scaleEffect(viewport.scale, anchor: .topLeading)
                .frame(width: viewport.contentSize.width, height: viewport.contentSize.height, alignment: .topLeading)
            }
            .scrollPosition($position)
            .overlay(alignment: .bottom) {
                controls(zoom: Double(viewport.scale))
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

    private func controls(zoom: Double) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                GraphSpeedLegend()
                Color.clear.frame(width: 0, height: 0)
            }
            Spacer(minLength: 0)
            GraphZoomControl(
                zoom: zoom,
                isFitting: userZoom == nil,
                onZoom: { userZoom = Self.clamp($0) },
                onFit: { userZoom = nil }
            )
        }
        .padding(16)
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }

    /// The automatic zoom: the graph fits across the window, never above
    /// 100 %. Height counts only down to 75 %, so a tall tree scrolls
    /// vertically instead of shrinking to unreadable text.
    static func fitZoom(content: CGSize, viewport: CGSize) -> Double {
        guard content.width > 0, content.height > 0, viewport.width > 0, viewport.height > 0 else { return 1 }
        let byWidth = Double(viewport.width / content.width)
        let byHeight = Double(viewport.height / content.height)
        let fit = min(1, byWidth, max(byHeight, 0.75))
        return clamp((fit * 20).rounded(.down) / 20)
    }

    /// True when the graph would show the Mac alone: no ports to draw and
    /// nothing in the Other group.
    private static func isOnlyHost(_ input: GraphInput) -> Bool {
        input.ports.isEmpty && input.otherDevices.isEmpty && input.otherDisplays.isEmpty
            && input.departingOther.isEmpty
    }

    /// Scrolls so the requested node sits in the middle of the window.
    private func scroll(to request: TopologyScrollRequest, layout: GraphLayout, viewport: GraphViewport, size: CGSize) {
        guard let tag = request.tag, let node = layout.nodes.first(where: { $0.tag == tag }) else { return }
        let target = viewport.scrollOffset(centering: node.frame, in: size)
        position.scrollTo(point: target)
        // Again once the scroll view has laid out content that just appeared.
        Task { @MainActor in
            withAnimation(.snappy) { position.scrollTo(point: target) }
        }
    }

    private func select(_ node: GraphNode) {
        guard let tag = node.tag, let selection = SelectionTag.selection(for: tag) else { return }
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
/// window sits in its middle.
nonisolated struct GraphViewport: Equatable {
    /// Canvas size at 100 % zoom.
    var canvasSize: CGSize
    /// Offset of the layout inside the canvas, at 100 % zoom.
    var origin: CGPoint
    var scale: CGFloat

    init(layout: CGSize, viewport: CGSize, scale: Double) {
        let scale = CGFloat(scale)
        let width = max(layout.width, (viewport.width / scale).rounded(.up))
        let height = max(layout.height, (viewport.height / scale).rounded(.up))
        canvasSize = CGSize(width: width, height: height)
        origin = CGPoint(x: ((width - layout.width) / 2).rounded(.down),
                         y: ((height - layout.height) / 2).rounded(.down))
        self.scale = scale
    }

    /// Size of the scroll view's content.
    var contentSize: CGSize {
        CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
    }

    /// The scroll offset that puts `rect` (layout coordinates) in the middle
    /// of a viewport of `size`, kept within the content.
    func scrollOffset(centering rect: CGRect, in size: CGSize) -> CGPoint {
        let x = (origin.x + rect.midX) * scale - size.width / 2
        let y = (origin.y + rect.midY) * scale - size.height / 2
        let maxX = max(0, contentSize.width - size.width)
        let maxY = max(0, contentSize.height - size.height)
        return CGPoint(x: min(max(0, x), maxX), y: min(max(0, y), maxY))
    }
}

/// The graph content at 100 % zoom: backdrop, links, pulses, chips and nodes.
/// The backdrop fills the canvas; everything else is drawn at `origin`.
struct GraphCanvas: View {
    var layout: GraphLayout
    var origin: CGPoint = .zero
    var snapshot: HostSnapshot
    var selectedTag: String?
    var dimmed: Set<String>
    var animate: Bool
    var onSelect: (GraphNode) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            GraphBackdrop(hostFrame: layout.hostNode?.frame.offsetBy(dx: origin.x, dy: origin.y))
            content
                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                .offset(x: origin.x, y: origin.y)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Topology map")
    }

    private var content: some View {
        ZStack(alignment: .topLeading) {
            GraphLinksLayer(strokes: GraphPaint.strokes(for: layout, dimmed: dimmed))
            GraphPulseLayer(tracks: GraphPaint.pulseTracks(for: layout, dimmed: dimmed), animate: animate)
            GraphChipsLayer(edges: layout.edges, dimmed: dimmed, maxChipWidth: layout.metrics.columnGap - 6)
            ForEach(layout.nodes) { node in
                GraphNodeView(
                    node: node,
                    snapshot: snapshot,
                    isSelected: node.tag != nil && node.tag == selectedTag,
                    isDimmed: dimmed.contains(node.id),
                    onSelect: { onSelect(node) }
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
