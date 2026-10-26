import BusStopCore
import CoreGraphics

/// What the Ports widget lists, fitted to the height it has: one block per
/// port in physical order, split into columns. Rows have fixed heights, so the
/// fit is exact; when the ports do not fit, the gaps shrink first, then trees
/// lose their last devices to a "+N more" line, then the last ports go to a
/// "+N more ports" line. Nothing is clipped.
public struct PortsWidgetLayout: Equatable {
    /// Fixed heights, in points.
    public enum Metrics {
        public static let portRow: CGFloat = 32
        public static let deviceRow: CGFloat = 18
        public static let gap: CGFloat = 10
        public static let minimumGap: CGFloat = 2
    }

    /// One port, and on the Extra Large widget the devices behind it.
    public struct Block: Equatable {
        public var port: PhysicalPort
        /// The devices under the port's row, depth 1 and deeper.
        public var tree: [Tree]
        /// Devices left out of `tree` for want of room.
        public var hiddenDevices = 0

        public struct Tree: Equatable {
            public var device: DeviceNode
            public var depth: Int
        }

        var height: CGFloat {
            Metrics.portRow + CGFloat(tree.count + (hiddenDevices > 0 ? 1 : 0)) * Metrics.deviceRow
        }
    }

    public var columns: [[Block]]
    /// Ports left off the end of the last column.
    public var hiddenPorts: Int
    /// The gap between blocks, the same in every column so rows line up.
    public var gap: CGFloat

    /// Lays out `ports` in `columnCount` columns of `height` points. `showsTrees`
    /// adds the devices behind each port's first device (or all of them, when
    /// several share the port).
    public init(ports: [PhysicalPort], showsTrees: Bool, columnCount: Int, height: CGFloat) {
        var shown = ports.map { Block(port: $0, tree: showsTrees ? Self.tree(of: $0) : []) }
        var hidden = 0
        var columns: [[Block]]
        while true {
            columns = Self.split(shown, into: max(columnCount, 1))
            let fits = columns.indices.allSatisfy { i in
                Self.trimTrees(&columns[i], height: height, reservesMoreLine: i == columns.count - 1 && hidden > 0)
            }
            // The last ports give way, so the ones shown stay in physical order.
            guard !fits, shown.count > 1 else { break }
            shown.removeLast()
            hidden += 1
        }
        let gaps = columns.enumerated().map { i, column in
            Self.largestGap(column, height: height, reservesMoreLine: i == columns.count - 1 && hidden > 0)
        }
        self.columns = columns
        hiddenPorts = hidden
        gap = gaps.min() ?? Metrics.gap
    }

    /// The devices under a port's row: behind its device when there is one,
    /// otherwise every device on it.
    static func tree(of port: PhysicalPort) -> [Block.Tree] {
        let roots = port.devices.count == 1 ? port.devices[0].children : port.devices
        return roots.flatMap { $0.flattened(depth: 1) }.map { Block.Tree(device: $0.device, depth: $0.depth) }
    }

    /// Height of `column` with `gap` between blocks, plus a "+N more ports" line.
    static func height(_ column: [Block], gap: CGFloat, reservesMoreLine: Bool = false) -> CGFloat {
        let blocks = column.reduce(0) { $0 + $1.height } + gap * CGFloat(max(column.count - 1, 0))
        return blocks + (reservesMoreLine ? gap + Metrics.deviceRow : 0)
    }

    /// Splits in physical order where the tallest column is shortest; on a
    /// tie the earlier columns take more.
    static func split(_ blocks: [Block], into count: Int) -> [[Block]] {
        guard count > 1, blocks.count > 1 else { return [blocks] + Array(repeating: [], count: count - 1) }
        // shortcut: tries every split point, so two columns only; generalise if a third is ever wanted.
        precondition(count == 2, "Ports widget layouts have one or two columns")
        let best = (1..<blocks.count).min { lhs, rhs in
            let l = max(height(Array(blocks[..<lhs]), gap: Metrics.gap), height(Array(blocks[lhs...]), gap: Metrics.gap))
            let r = max(height(Array(blocks[..<rhs]), gap: Metrics.gap), height(Array(blocks[rhs...]), gap: Metrics.gap))
            return l < r || (l == r && lhs > rhs)
        }!
        return [Array(blocks[..<best]), Array(blocks[best...])]
    }

    /// Trims trees in `column` until it fits at the minimum gap; false when even bare rows do not.
    static func trimTrees(_ column: inout [Block], height limit: CGFloat, reservesMoreLine: Bool) -> Bool {
        while height(column, gap: Metrics.minimumGap, reservesMoreLine: reservesMoreLine) > limit {
            // The longest tree gives up its last device; the earlier port's on a tie.
            guard let i = column.indices.filter({ !column[$0].tree.isEmpty })
                .max(by: { column[$0].tree.count < column[$1].tree.count }) else { return false }
            column[i].tree.removeLast()
            column[i].hiddenDevices += 1
        }
        return true
    }

    /// The widest gap, up to `Metrics.gap`, at which `column` still fits.
    static func largestGap(_ column: [Block], height limit: CGFloat, reservesMoreLine: Bool) -> CGFloat {
        let spaces = CGFloat(max(column.count - 1, 0) + (reservesMoreLine ? 1 : 0))
        guard spaces > 0 else { return Metrics.gap }
        let fixed = height(column, gap: 0, reservesMoreLine: reservesMoreLine)
        return min(Metrics.gap, max(Metrics.minimumGap, ((limit - fixed) / spaces).rounded(.down)))
    }
}
