import BusStopCore
import CoreGraphics
import Foundation

// A deterministic, pure layout for the topology graph. Everything here is
// plain value types computed from the snapshot, so it can be unit-tested and
// never depends on view measurement.
//
// Columns, left to right:
//   0  the host (the Mac)
//   1  one node per port, in the order given, then an optional "Other" group
//   2+ devices by depth below their port
//
// Each port block is as tall as its device subtree needs: leaves stack
// vertically, and every parent is centred on its children, so a subtree gets
// vertical space in proportion to its leaf count.

/// Sizes and spacing used by `GraphLayout`, in points at 100 % zoom.
nonisolated struct GraphMetrics: Sendable, Equatable {
    var hostSize = CGSize(width: 232, height: 150)
    var portSize = CGSize(width: 252, height: 80)
    var deviceSize = CGSize(width: 232, height: 58)
    var columnGap: CGFloat = 90
    var rowGap: CGFloat = 14
    /// Extra space between one port's block and the next.
    var groupGap: CGFloat = 24
    var padding: CGFloat = 40

    static let standard = GraphMetrics()

    /// Node sizes grow with `factor` (for larger text); gaps grow more gently.
    func scaled(by factor: CGFloat) -> GraphMetrics {
        guard factor != 1 else { return self }
        var copy = self
        copy.hostSize = CGSize(width: hostSize.width * factor, height: hostSize.height * factor)
        copy.portSize = CGSize(width: portSize.width * factor, height: portSize.height * factor)
        copy.deviceSize = CGSize(width: deviceSize.width * factor, height: deviceSize.height * factor)
        let gentle = 1 + (factor - 1) / 2
        copy.columnGap = columnGap * gentle
        copy.rowGap = rowGap * gentle
        copy.groupGap = groupGap * gentle
        return copy
    }
}

/// What the layout is computed from.
nonisolated struct GraphInput: Sendable {
    /// Ports in display order (column 1, top to bottom).
    var ports: [PhysicalPort]
    /// Devices that could not be tied to a port (shown under "Other").
    var otherDevices: [DeviceNode] = []
    /// External displays that could not be tied to a port.
    var otherDisplays: [DisplayInfo] = []
    /// Displays known to be on a port but missing from that port's device tree.
    var portDisplays: [PortKey: [DisplayInfo]] = [:]
    /// Devices that just disappeared, drawn as fading ghosts.
    var departingByPort: [PortKey: [DeviceNode]] = [:]
    var departingOther: [DeviceNode] = []
}

/// What a node shows.
nonisolated enum GraphNodeContent: Sendable {
    case host
    case port(PhysicalPort)
    /// The "Other" group; `count` is the number of items under it.
    case otherGroup(count: Int)
    case device(DeviceNode, isDeparting: Bool)
    case display(DisplayInfo)
}

/// One positioned node.
nonisolated struct GraphNode: Identifiable, Sendable {
    /// Unique within a layout.
    var id: String
    var content: GraphNodeContent
    /// 0 host, 1 ports, 2+ devices by depth.
    var column: Int
    var frame: CGRect
    var parentID: String?
    /// The port this node hangs off; nil for the host, the Other group and its members.
    var portKey: PortKey?
    /// Selection tag (`SelectionTag` format), or nil when the node cannot be selected.
    var tag: String?
}

/// A cubic Bézier from the right edge of one node to the left edge of another,
/// with horizontal tangents at both ends.
nonisolated struct GraphCurve: Sendable, Equatable {
    var start: CGPoint
    var control1: CGPoint
    var control2: CGPoint
    var end: CGPoint

    init(from start: CGPoint, to end: CGPoint) {
        self.start = start
        self.end = end
        let reach = max(abs(end.x - start.x) * 0.5, 24)
        control1 = CGPoint(x: start.x + reach, y: start.y)
        control2 = CGPoint(x: end.x - reach, y: end.y)
    }

    /// The point at parameter `t` (0…1).
    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return CGPoint(
            x: a * start.x + b * control1.x + c * control2.x + d * end.x,
            y: a * start.y + b * control1.y + c * control2.y + d * end.y
        )
    }

    var midpoint: CGPoint { point(at: 0.5) }
}

/// Whether an edge joins the host to a port or carries a device link.
nonisolated enum GraphEdgeKind: Sendable, Equatable {
    /// Host to a port, or host to the Other group: thin and muted.
    case trunk
    /// Port or device to a child device: coloured by the child's link speed.
    case link
}

/// One positioned connection.
nonisolated struct GraphEdge: Identifiable, Sendable {
    var id: String
    var fromID: String
    var toID: String
    var kind: GraphEdgeKind
    var curve: GraphCurve
    /// Drives colour, width, chip and pulse speed (the child's link, or the port's for trunks).
    var link: LinkInfo?
    /// Something live is at the far end.
    var isActive: Bool
    /// Empty ports, the Other group and departing devices are drawn dashed.
    var isDashed: Bool
    var isDeparting: Bool
    /// Where the speed chip sits; nil when the edge has no chip.
    var chipPoint: CGPoint?
}

/// The computed graph: positioned nodes and edges plus the canvas size.
nonisolated struct GraphLayout: Sendable {
    static let hostID = "host"
    static let otherID = "other"

    var nodes: [GraphNode]
    var edges: [GraphEdge]
    var size: CGSize
    var metrics: GraphMetrics

    static func portID(_ key: PortKey) -> String { "port:\(key)" }
    static func deviceID(_ id: String) -> String { "device:\(id)" }
    static func displayID(_ id: String) -> String { "display:\(id)" }
    static func departingID(_ id: String) -> String { "departing:\(id)" }

    var hostNode: GraphNode? { nodes.first { $0.id == Self.hostID } }

    func node(id: String) -> GraphNode? { nodes.first { $0.id == id } }

    /// Lays out `input`. Pure: the same input and metrics give the same result.
    static func make(_ input: GraphInput, metrics: GraphMetrics = .standard) -> GraphLayout {
        var builder = GraphLayoutBuilder(metrics: metrics)
        builder.build(input)
        return builder.result
    }
}

// MARK: - Builder

private nonisolated struct GraphLayoutBuilder {
    /// A child under a port or device, before placement.
    nonisolated enum Item {
        case device(DeviceNode, isDeparting: Bool)
        case display(DisplayInfo)

        var leafCount: Int {
            switch self {
            case .display: return 1
            case .device(let device, let isDeparting):
                return isDeparting ? 1 : GraphLayoutBuilder.leafCount(device)
            }
        }
    }

    /// A placed child, reported back to its parent so the parent can draw the edge.
    nonisolated struct Placed {
        var id: String
        var frame: CGRect
        var height: CGFloat
        var link: LinkInfo?
        var isDeparting: Bool
    }

    /// A port or the Other group, before placement.
    nonisolated struct Group {
        var id: String
        var content: GraphNodeContent
        var portKey: PortKey?
        var tag: String?
        var items: [Item]
        var trunkLink: LinkInfo?
        var isActive: Bool
        var isDashed: Bool
    }

    let metrics: GraphMetrics
    var nodes: [GraphNode] = []
    var edges: [GraphEdge] = []
    var usedIDs: Set<String> = []

    init(metrics: GraphMetrics) {
        self.metrics = metrics
    }

    var result: GraphLayout {
        let maxX = nodes.map(\.frame.maxX).max() ?? metrics.padding
        let maxY = nodes.map(\.frame.maxY).max() ?? metrics.padding
        return GraphLayout(
            nodes: nodes,
            edges: edges,
            size: CGSize(width: ceil(maxX + metrics.padding), height: ceil(maxY + metrics.padding)),
            metrics: metrics
        )
    }

    // MARK: Geometry

    var portX: CGFloat { metrics.padding + metrics.hostSize.width + metrics.columnGap }

    func deviceX(depth: Int) -> CGFloat {
        portX + metrics.portSize.width + metrics.columnGap
            + CGFloat(depth) * (metrics.deviceSize.width + metrics.columnGap)
    }

    /// Height of `leaves` stacked device nodes.
    func stackHeight(leaves: Int) -> CGFloat {
        guard leaves > 0 else { return 0 }
        return CGFloat(leaves) * metrics.deviceSize.height + CGFloat(leaves - 1) * metrics.rowGap
    }

    func blockHeight(_ group: Group) -> CGFloat {
        let leaves = group.items.reduce(0) { $0 + $1.leafCount }
        return max(metrics.portSize.height, stackHeight(leaves: leaves))
    }

    static func leafCount(_ device: DeviceNode) -> Int {
        device.children.isEmpty ? 1 : device.children.reduce(0) { $0 + leafCount($1) }
    }

    /// IDs must be unique for SwiftUI; a repeated device gets a numeric suffix.
    mutating func uniqueID(_ base: String) -> String {
        var candidate = base
        var counter = 2
        while usedIDs.contains(candidate) {
            candidate = "\(base)#\(counter)"
            counter += 1
        }
        usedIDs.insert(candidate)
        return candidate
    }

    // MARK: Build

    mutating func build(_ input: GraphInput) {
        usedIDs.insert(GraphLayout.hostID)
        var groups: [Group] = []
        for port in input.ports {
            var items: [Item] = port.devices.map { .device($0, isDeparting: false) }
            items += (input.portDisplays[port.key] ?? []).map { .display($0) }
            items += (input.departingByPort[port.key] ?? []).map { .device($0, isDeparting: true) }
            groups.append(Group(
                id: uniqueID(GraphLayout.portID(port.key)),
                content: .port(port),
                portKey: port.key,
                tag: GraphLayout.portID(port.key),
                items: items,
                trunkLink: port.link,
                isActive: port.isConnected,
                isDashed: !port.isConnected
            ))
        }

        var otherItems: [Item] = input.otherDevices.map { .device($0, isDeparting: false) }
        otherItems += input.otherDisplays.map { .display($0) }
        otherItems += input.departingOther.map { .device($0, isDeparting: true) }
        if !otherItems.isEmpty {
            let count = input.otherDevices.reduce(0) { $0 + 1 + $1.descendantCount } + input.otherDisplays.count
            groups.append(Group(
                id: uniqueID(GraphLayout.otherID),
                content: .otherGroup(count: count),
                portKey: nil,
                tag: nil,
                items: otherItems,
                trunkLink: nil,
                isActive: false,
                isDashed: true
            ))
        }

        // Centre the port column against the host when the host is taller.
        let heights = groups.map { blockHeight($0) }
        let contentHeight = heights.reduce(0, +) + CGFloat(max(groups.count - 1, 0)) * metrics.groupGap
        var top = metrics.padding + max(0, (metrics.hostSize.height - contentHeight) / 2)

        var groupFrames: [(group: Group, frame: CGRect)] = []
        for (group, height) in zip(groups, heights) {
            let frame = place(group, top: top, blockHeight: height)
            groupFrames.append((group, frame))
            top += height + metrics.groupGap
        }

        // Host, centred on the port column.
        let columnTop = metrics.padding + max(0, (metrics.hostSize.height - contentHeight) / 2)
        let hostCenterY = groups.isEmpty
            ? metrics.padding + metrics.hostSize.height / 2
            : columnTop + contentHeight / 2
        let hostFrame = CGRect(
            x: metrics.padding,
            y: max(metrics.padding, hostCenterY - metrics.hostSize.height / 2),
            width: metrics.hostSize.width,
            height: metrics.hostSize.height
        )
        nodes.append(GraphNode(id: GraphLayout.hostID, content: .host, column: 0, frame: hostFrame,
                               parentID: nil, portKey: nil, tag: SelectionTagFormat.host))

        // Trunks fan out from a short "bus" along the host's right edge.
        let count = groupFrames.count
        let spread = count > 1 ? min(10, (metrics.hostSize.height - 56) / CGFloat(count - 1)) : 0
        for (index, entry) in groupFrames.enumerated() {
            let offset = (CGFloat(index) - CGFloat(count - 1) / 2) * spread
            let start = CGPoint(x: hostFrame.maxX, y: hostFrame.midY + offset)
            let end = CGPoint(x: entry.frame.minX, y: entry.frame.midY)
            edges.append(GraphEdge(
                id: "\(GraphLayout.hostID)->\(entry.group.id)",
                fromID: GraphLayout.hostID,
                toID: entry.group.id,
                kind: .trunk,
                curve: GraphCurve(from: start, to: end),
                link: entry.group.trunkLink,
                isActive: entry.group.isActive,
                isDashed: entry.group.isDashed,
                isDeparting: false,
                chipPoint: nil
            ))
        }
    }

    /// Places a port (or the Other group) and its subtree inside a block that
    /// starts at `top`. Returns the group node's frame.
    mutating func place(_ group: Group, top: CGFloat, blockHeight: CGFloat) -> CGRect {
        let size = metrics.portSize
        let centerY = top + blockHeight / 2
        let frame = CGRect(x: portX, y: centerY - size.height / 2, width: size.width, height: size.height)
        nodes.append(GraphNode(id: group.id, content: group.content, column: 1, frame: frame,
                               parentID: GraphLayout.hostID, portKey: group.portKey, tag: group.tag))

        let leaves = group.items.reduce(0) { $0 + $1.leafCount }
        var childTop = top + (blockHeight - stackHeight(leaves: leaves)) / 2
        for item in group.items {
            let placed = place(item, depth: 0, top: childTop, parentID: group.id, portKey: group.portKey)
            addLinkEdge(fromID: group.id, fromFrame: frame, to: placed)
            childTop += placed.height + metrics.rowGap
        }
        return frame
    }

    /// Places one device (and its children) with its subtree starting at `top`.
    mutating func place(_ item: Item, depth: Int, top: CGFloat, parentID: String, portKey: PortKey?) -> Placed {
        let size = metrics.deviceSize
        let x = deviceX(depth: depth)

        switch item {
        case .display(let display):
            let id = uniqueID(GraphLayout.displayID(display.id))
            let frame = CGRect(x: x, y: top, width: size.width, height: size.height)
            nodes.append(GraphNode(id: id, content: .display(display), column: depth + 2, frame: frame,
                                   parentID: parentID, portKey: portKey, tag: GraphLayout.displayID(display.id)))
            return Placed(id: id, frame: frame, height: size.height, link: display.link, isDeparting: false)

        case .device(let device, let isDeparting):
            let baseID = isDeparting ? GraphLayout.departingID(device.id) : GraphLayout.deviceID(device.id)
            let id = uniqueID(baseID)
            let tag = isDeparting ? nil : GraphLayout.deviceID(device.id)
            let children = isDeparting ? [] : device.children

            var placedChildren: [Placed] = []
            var childTop = top
            for child in children {
                let placed = place(.device(child, isDeparting: false), depth: depth + 1, top: childTop,
                                   parentID: id, portKey: portKey)
                placedChildren.append(placed)
                childTop += placed.height + metrics.rowGap
            }

            let frame: CGRect
            let height: CGFloat
            if let first = placedChildren.first, let last = placedChildren.last {
                let centerY = (first.frame.midY + last.frame.midY) / 2
                frame = CGRect(x: x, y: centerY - size.height / 2, width: size.width, height: size.height)
                height = max(childTop - metrics.rowGap - top, size.height)
            } else {
                frame = CGRect(x: x, y: top, width: size.width, height: size.height)
                height = size.height
            }

            nodes.append(GraphNode(id: id, content: .device(device, isDeparting: isDeparting), column: depth + 2,
                                   frame: frame, parentID: parentID, portKey: portKey, tag: tag))
            for placed in placedChildren {
                addLinkEdge(fromID: id, fromFrame: frame, to: placed)
            }
            return Placed(id: id, frame: frame, height: height, link: device.link, isDeparting: isDeparting)
        }
    }

    mutating func addLinkEdge(fromID: String, fromFrame: CGRect, to child: Placed) {
        let start = CGPoint(x: fromFrame.maxX, y: fromFrame.midY)
        let end = CGPoint(x: child.frame.minX, y: child.frame.midY)
        let curve = GraphCurve(from: start, to: end)
        let showsChip = child.link != nil && !child.isDeparting
        edges.append(GraphEdge(
            id: "\(fromID)->\(child.id)",
            fromID: fromID,
            toID: child.id,
            kind: .link,
            curve: curve,
            link: child.link,
            isActive: !child.isDeparting,
            isDashed: child.isDeparting,
            isDeparting: child.isDeparting,
            chipPoint: showsChip ? curve.midpoint : nil
        ))
    }
}

/// The host's selection tag, duplicated here so the layout stays free of
/// main-actor types (it must match `SelectionTag.host`).
private nonisolated enum SelectionTagFormat {
    static let host = "host"
}
