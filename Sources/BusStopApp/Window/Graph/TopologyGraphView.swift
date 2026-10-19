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
    /// Where the map looks; nil fits the graph to the window.
    @Binding var camera: GraphCamera?
    /// False while the window is closed, minimised or covered: pulses pause.
    var isWindowVisible: Bool
    /// A node to scroll into view; cleared once handled.
    @Binding var scrollRequest: TopologyScrollRequest?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.lagoonTextScale) private var textScale
    /// Links show data rates or power.
    @AppStorage(TopologyWindowDefaults.linkMode) private var linkMode: GraphLinkMode = .data

    /// Zoom chosen with the buttons, the scroll wheel or a pinch.
    static let zoomRange: ClosedRange<Double> = 0.25...2.0
    /// Fitting the window never goes below this, so text stays readable; a
    /// larger graph is panned instead.
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

    /// The map reads the camera itself, so moving it redraws only the map,
    /// not the layout or the strokes computed here.
    private func graph(_ layout: GraphLayout) -> some View {
        let dimmed = dimmedNodeIDs(in: layout)
        let powers = linkMode == .power ? GraphPaint.powers(for: layout) : [:]
        let strokes = GraphPaint.strokes(for: layout, dimmed: dimmed, mode: linkMode, powers: powers)
        let tracks = GraphPaint.pulseTracks(for: layout, dimmed: dimmed, mode: linkMode, powers: powers)
        return GeometryReader { proxy in
            GraphMap(
                layout: layout,
                strokes: strokes,
                pulseTracks: tracks,
                linkMode: $linkMode,
                powers: powers,
                snapshot: store.snapshot,
                selectedTag: SelectionTag.string(for: store.selection),
                dimmed: dimmed,
                animate: store.settings.animateLinks && !reduceMotion && isWindowVisible,
                size: proxy.size,
                camera: $camera,
                scrollRequest: $scrollRequest,
                onSelect: select,
                onSelectLink: selectLink
            )
        }
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }

    /// The automatic zoom: the graph fits across the window, never above
    /// 100 % or below `minimumFitZoom`. Height counts only down to 75 %, so a
    /// tall tree is panned vertically instead of shrinking to unreadable text.
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

/// A pinch in progress: how far it has zoomed, and where it started.
nonisolated struct GraphPinch: Equatable {
    var magnification: CGFloat
    var location: CGPoint
}

/// The map itself: backdrop, links, pulses, chips and cards, drawn through a
/// `GraphCamera` at the size of the view, with the zoom controls on top.
///
/// Dragging anywhere pans; a mouse wheel zooms around the pointer; a
/// trackpad scroll pans and a pinch zooms. A drag or pinch moves the camera
/// only on screen until it ends, then commits it, so a new gesture always
/// starts from where the last one left the map. Under the cards, one hit
/// layer finds the link nearest the pointer, highlights it on hover and
/// selects it on click. Cards sit above it and keep their own clicks.
///
/// Chips and badges get the map's own tooltips (`GraphTooltipState`); the
/// picker and zoom buttons keep the system's, each in its own hosting view
/// (`GraphControlHost`).
struct GraphMap: View {
    var layout: GraphLayout
    var strokes: [GraphEdgeStroke]
    var pulseTracks: [GraphPulseTrack]
    @Binding var linkMode: GraphLinkMode
    var powers: [String: GraphEdgePower]
    var snapshot: HostSnapshot
    var selectedTag: String?
    var dimmed: Set<String>
    var animate: Bool
    var size: CGSize
    @Binding var camera: GraphCamera?
    @Binding var scrollRequest: TopologyScrollRequest?
    var onSelect: (GraphNode) -> Void
    /// Called with the tag of the node a clicked link leads to.
    var onSelectLink: (String) -> Void

    @State private var hoveredEdgeID: String?
    /// Set once a drag has moved far enough to count as a pan, so the click
    /// that ends it does not also select a card or a link.
    @State private var didPan = false
    /// Never read in `body`: only the tooltip overlay observes it.
    @State private var tooltip = GraphTooltipState()
    @GestureState private var drag: CGSize = .zero
    @GestureState private var pinch: GraphPinch?

    /// The camera at rest: the user's, or the one that fits the window. The
    /// user's is kept on the graph here too, since the graph can shrink
    /// under it (a device unplugged) after it was committed.
    private var base: GraphCamera {
        camera.map { $0.clamped(layout: layout.size, viewport: size) }
            ?? GraphCamera.fit(layout: layout.size, viewport: size,
                               scale: CGFloat(TopologyGraphView.fitZoom(content: layout.size, viewport: size)))
    }

    /// The camera on screen: `base` with a drag or pinch in progress.
    private var live: GraphCamera {
        var live = base
        if let pinch { live = live.zoomed(to: Self.clamp(live.scale * pinch.magnification), at: pinch.location) }
        return live.panned(by: drag)
    }

    var body: some View {
        let camera = live
        // A little beyond the edges, so glows and chips do not pop in.
        let margin = 40 / camera.scale
        let visible = camera.visibleLayoutRect(in: size).insetBy(dx: -margin, dy: -margin)
        let shown = strokes.filter { $0.path.boundingRect.intersects(visible) }.map { $0.viewed(through: camera) }
        let selectedLinks = SelectionTag.linkTarget(of: selectedTag).map { layout.edgeIDs(leadingTo: $0) } ?? []
        let highlighted = shown.filter { selectedLinks.contains($0.id) || $0.id == hoveredEdgeID }
        ZStack(alignment: .topLeading) {
            GraphBackdrop(hostFrame: layout.hostNode?.frame, camera: camera)
            hitLayer(camera)
            GraphLinksLayer(strokes: shown, scale: camera.scale)
            GraphLinkHighlightLayer(strokes: highlighted, selected: selectedLinks, hovered: hoveredEdgeID,
                                    scale: camera.scale)
            // Pulses rest while the map moves, so moving stays smooth.
            GraphPulseLayer(tracks: pulseTracks.filter { $0.curve.path.boundingRect.intersects(visible) },
                            camera: camera, animate: animate && drag == .zero && pinch == nil)
            ZStack(alignment: .topLeading) {
                GraphChipsLayer(edges: layout.edges.filter { $0.chipPoint.map(visible.contains) ?? false },
                                dimmed: dimmed, maxChipWidth: layout.metrics.columnGap - 6, camera: camera,
                                mode: linkMode, powers: powers)
                ForEach(layout.nodes.filter { $0.frame.intersects(visible) }) { node in
                    GraphNodeView(
                        node: node,
                        snapshot: snapshot,
                        isSelected: node.tag != nil && node.tag == selectedTag,
                        isDimmed: dimmed.contains(node.id),
                        onSelect: { if !didPan { onSelect(node) } },
                        onPointer: { tooltip.cardPointerMoved(node.id, to: $0) }
                    )
                    .frame(width: node.frame.width, height: node.frame.height)
                    .scaleEffect(camera.scale)
                    .position(camera.screenPoint(CGPoint(x: node.frame.midX, y: node.frame.midY)))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // `scaleEffect` alone enlarges a bitmap drawn at 100 %, so cards
            // and chips went soft above 100 %. A drawing group renders them
            // after the zoom, at the screen's resolution. Everything inside
            // must be pure SwiftUI drawing (text, shapes, SF Symbols): a
            // drawing group shows glass, materials, `ProgressView`, `Menu`,
            // `TextField`, system-styled controls and `NSViewRepresentable`s
            // as placeholders. It also cannot draw the system focus ring, so
            // `GraphNodeView` draws its own. See docs/decisions.md.
            .drawingGroup()
            // Chips inside publish tooltip regions instead of using `.help`.
            .environment(\.showsChipHelp, false)
            .onPreferenceChange(GraphTooltipRegionsKey.self) { tooltip.setRegions($0) }
            // Outside the drawing group, so it is not zoomed.
            GraphTooltipOverlay(state: tooltip, camera: camera, size: size)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        // The canvases cannot animate, so neither do the cards when the
        // map's size changes (the inspector sliding in): they move together.
        .transaction(value: size) { $0.animation = nil }
        .clipped()
        .contentShape(Rectangle())
        // While panning, the closed hand shows over the cards too.
        .pointerStyle(drag != .zero ? PointerStyle.grabActive : nil)
        .simultaneousGesture(panGesture)
        .simultaneousGesture(pinchGesture)
        .background {
            GraphScrollWheelZoom { factor, location in
                tooltip.dismiss()
                commit(base.zoomed(to: Self.clamp(base.scale * factor), at: location))
            } onPan: { translation in
                tooltip.dismiss()
                commit(base.panned(by: translation))
            } onMouseDown: {
                tooltip.dismiss()
            }
        }
        .overlay(alignment: .bottom) { controls(zoom: camera.scale) }
        .onChange(of: drag == .zero) { _, isIdle in
            guard isIdle else { return }
            // Let the click that ended the pan go by first.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                didPan = false
            }
        }
        // A tooltip stays where its chip was, so it goes when the map moves.
        .onChange(of: camera) { tooltip.cameraMoved() }
        .onChange(of: linkMode) { tooltip.dismiss() }
        .onChange(of: size) { old, new in
            // A resized window (the inspector opening, say) keeps the middle
            // of the map in the middle.
            guard let current = self.camera else { return }
            commit(current.panned(by: CGSize(width: (new.width - old.width) / 2, height: (new.height - old.height) / 2)))
        }
        .onChange(of: scrollRequest, initial: true) { _, request in
            guard let request else { return }
            scrollRequest = nil
            reveal(request)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Topology map")
    }

    private static func clamp(_ scale: CGFloat) -> CGFloat {
        CGFloat(TopologyGraphView.clamp(Double(scale)))
    }

    /// Makes `next` the user's camera, keeping part of the graph on screen.
    private func commit(_ next: GraphCamera) {
        let clamped = next.clamped(layout: layout.size, viewport: size)
        if clamped != camera { camera = clamped }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($drag) { value, state, _ in state = value.translation }
            .onChanged { value in
                if !didPan, hypot(value.translation.width, value.translation.height) > 4 { didPan = true }
            }
            .onEnded { value in commit(base.panned(by: value.translation)) }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in
                state = GraphPinch(magnification: value.magnification, location: value.startLocation)
            }
            .onEnded { value in
                commit(base.zoomed(to: Self.clamp(base.scale * value.magnification), at: value.startLocation))
            }
    }

    /// Hover and click targets for the links, over the whole map.
    private func hitLayer(_ camera: GraphCamera) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                var hovered: String?
                var pointer: CGPoint?
                if case .active(let location) = phase {
                    hovered = edge(at: location, camera)?.id
                    pointer = camera.layoutPoint(location)
                }
                if hovered != hoveredEdgeID { hoveredEdgeID = hovered }
                // Link chips never take the pointer, so their tooltips
                // come from here.
                tooltip.mapPointerMoved(to: pointer)
            }
            .onTapGesture { location in
                guard !didPan, let edge = edge(at: location, camera), let tag = layout.childTag(of: edge) else { return }
                onSelectLink(tag)
            }
            .pointerStyle(hitLayerPointer)
            .accessibilityHidden(true)
    }

    /// An open hand over the map, a closed one while panning, a pointing
    /// hand over a link.
    private var hitLayerPointer: PointerStyle {
        if drag != .zero { return .grabActive }
        return hoveredEdgeID != nil ? .link : .grabIdle
    }

    /// The selectable link within about 6 points of `location` on screen.
    private func edge(at location: CGPoint, _ camera: GraphCamera) -> GraphEdge? {
        layout.edge(near: camera.layoutPoint(location), tolerance: 6 / camera.scale)
    }

    /// Moves the map so the requested card (or the middle of a link) is in
    /// the middle, unless it is already well inside the view.
    private func reveal(_ request: TopologyScrollRequest) {
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
        let current = base
        let topLeft = current.screenPoint(rect.origin)
        let onScreen = CGRect(x: topLeft.x, y: topLeft.y, width: rect.width * current.scale, height: rect.height * current.scale)
        guard !CGRect(origin: .zero, size: size).insetBy(dx: 24, dy: 24).contains(onScreen) else { return }
        commit(current.centering(rect, in: size))
    }

    /// The picker and the zoom cluster each sit in their own hosting view, so
    /// their tooltips do not depend on the map's (see `GraphControlHost`).
    private func controls(zoom: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            GraphLinkModePicker(linkMode: $linkMode)
            ViewThatFits(in: .horizontal) {
                switch linkMode {
                case .data: GraphSpeedLegend()
                case .power: GraphPowerLegend()
                }
                Color.clear.frame(width: 0, height: 0)
            }
            Spacer(minLength: 0)
            GraphControlHost {
                GraphZoomControl(
                    zoom: Double(zoom),
                    isFitting: camera == nil,
                    // Buttons zoom around the middle of the map.
                    onZoom: { target in
                        commit(base.zoomed(to: Self.clamp(CGFloat(target)),
                                           at: CGPoint(x: size.width / 2, y: size.height / 2)))
                    },
                    onFit: { camera = nil }
                )
            }
            .fixedSize()
        }
        .padding(16)
    }
}

/// The Data / Power toggle, in its own hosting view (see `GraphControlHost`).
/// The map and the Mac Outline share it and its saved choice.
struct GraphLinkModePicker: View {
    @Binding var linkMode: GraphLinkMode

    var body: some View {
        GraphControlHost {
            Picker("Colour by", selection: $linkMode) {
                ForEach(GraphLinkMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Colour by data rate or by power")
        }
        .fixedSize()
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

/// Key for the power colours: one swatch per power tier, and what "≤" means.
struct GraphPowerLegend: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            ForEach(PowerTier.allCases, id: \.self) { tier in
                HStack(spacing: 5) {
                    Capsule()
                        .fill(Lagoon.powerColor(tier))
                        .frame(width: 16, height: Lagoon.powerWidth(tier))
                        .lagoonGlow(Lagoon.powerGlows(tier) ? Lagoon.powerColor(tier).opacity(0.7) : .clear, radius: 3)
                    Text(Self.title(tier))
                        .lagoonFont(.caption2, weight: .medium, monospacedDigits: true)
                        .foregroundStyle(Lagoon.textSecondary)
                        .fixedSize()
                }
            }
            Text("≤ USB budget")
                .lagoonFont(.caption2, weight: .medium)
                .foregroundStyle(Lagoon.textTertiary)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Lagoon.surface.opacity(0.94)))
        .overlay(Capsule().strokeBorder(WindowContrast.stroke(contrast), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText(colorScheme))
    }

    /// The legend's spoken text: the ramp runs the other way in Light.
    static func accessibilityText(_ scheme: ColorScheme) -> String {
        let ramp = scheme == .dark
            ? "deep red, orange, amber and gold"
            : "dark gold, amber, rust and deep red"
        return "Power colours: grey for no power, then \(ramp) as watts rise. Pulses move the way the power flows. Values marked with a less-than-or-equal sign are USB power budgets, not measurements."
    }

    static func title(_ tier: PowerTier) -> String {
        switch tier {
        case .none: return "None"
        case .under5: return "< 5 W"
        case .under15: return "5–15 W"
        case .under45: return "15–45 W"
        case .high: return "45 W+"
        }
    }
}

/// Key for the link colours: one swatch per speed tier.
struct GraphSpeedLegend: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            ForEach(SpeedTier.allCases, id: \.self) { tier in
                HStack(spacing: 5) {
                    Capsule()
                        .fill(Lagoon.linkColor(tier))
                        .frame(width: 16, height: Lagoon.linkWidth(tier))
                        .lagoonGlow(Lagoon.linkGlows(tier) ? Lagoon.linkColor(tier).opacity(0.7) : .clear, radius: 3)
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
        .accessibilityLabel(Self.accessibilityText(colorScheme))
    }

    /// The legend's spoken text: Light draws faster links darker, with no glow.
    static func accessibilityText(_ scheme: ColorScheme) -> String {
        scheme == .dark
            ? "Link colours: dim for USB 2, brighter and thicker for faster links, glowing at 40 gigabits per second and above"
            : "Link colours: pale for USB 2, darker and thicker for faster links"
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
