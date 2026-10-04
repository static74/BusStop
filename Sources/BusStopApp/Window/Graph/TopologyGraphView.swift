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

    @AppStorage("topologyGraphZoom") private var zoom: Double = 1
    @GestureState private var pinch: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let zoomRange: ClosedRange<Double> = 0.5...1.5

    var body: some View {
        let settings = store.settings
        let layout = GraphLayout.make(graphInput, metrics: GraphMetrics.standard.scaled(by: settings.textSize.graphScale))
        let dimmed = dimmedNodeIDs(in: layout)
        let scale = Self.clamp(zoom * Double(pinch))
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                GraphCanvas(
                    layout: layout,
                    snapshot: store.snapshot,
                    selectedTag: SelectionTag.string(for: store.selection),
                    dimmed: dimmed,
                    animate: settings.animateLinks && !reduceMotion,
                    onSelect: select
                )
                .frame(width: layout.size.width, height: layout.size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: layout.size.width * scale, height: layout.size.height * scale, alignment: .topLeading)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .overlay(alignment: .bottomTrailing) {
                GraphZoomControl(zoom: $zoom, fitZoom: fitZoom(content: layout.size, viewport: proxy.size))
                    .padding(16)
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in zoom = Self.clamp(zoom * Double(value.magnification)) }
        )
    }

    static func clamp(_ value: Double) -> Double {
        min(max(value, zoomRange.lowerBound), zoomRange.upperBound)
    }

    private func fitZoom(content: CGSize, viewport: CGSize) -> Double {
        guard content.width > 0, content.height > 0 else { return 1 }
        let fit = min(Double(viewport.width / content.width), Double(viewport.height / content.height))
        return Self.clamp((fit * 20).rounded(.down) / 20)
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

/// The graph content at 100 % zoom: backdrop, links, pulses, chips and nodes.
struct GraphCanvas: View {
    var layout: GraphLayout
    var snapshot: HostSnapshot
    var selectedTag: String?
    var dimmed: Set<String>
    var animate: Bool
    var onSelect: (GraphNode) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            GraphBackdrop(hostFrame: layout.hostNode?.frame)
            GraphLinksLayer(strokes: GraphPaint.strokes(for: layout, dimmed: dimmed))
            GraphPulseLayer(tracks: GraphPaint.pulseTracks(for: layout, dimmed: dimmed), animate: animate)
            GraphChipsLayer(edges: layout.edges, dimmed: dimmed)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Topology map")
    }
}

/// Glass zoom cluster in the graph's corner: zoom out, actual size, zoom in, fit.
struct GraphZoomControl: View {
    @Binding var zoom: Double
    var fitZoom: Double

    var body: some View {
        let tint = AppSettings.shared.glassTint
        GlassEffectContainer {
            HStack(spacing: 2) {
                iconButton("minus.magnifyingglass", help: "Zoom Out") { step(-0.1) }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(zoom <= TopologyGraphView.zoomRange.lowerBound)
                Button {
                    zoom = 1
                } label: {
                    Text("\(Int((zoom * 100).rounded()))%")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Lagoon.textPrimary)
                        .frame(minWidth: 42, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("0", modifiers: .command)
                .help("Actual Size")
                .accessibilityLabel("Zoom \(Int((zoom * 100).rounded())) percent. Reset to actual size")
                iconButton("plus.magnifyingglass", help: "Zoom In") { step(0.1) }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(zoom >= TopologyGraphView.zoomRange.upperBound)
                Rectangle()
                    .fill(Lagoon.stroke)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 3)
                iconButton("arrow.up.left.and.down.right.magnifyingglass", help: "Zoom to Fit") {
                    zoom = fitZoom
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassEffect(.regular.tint(Lagoon.accent.opacity(tint)).interactive(), in: .capsule)
        }
    }

    private func step(_ delta: Double) {
        zoom = TopologyGraphView.clamp(((zoom + delta) * 10).rounded() / 10)
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Lagoon.textPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
