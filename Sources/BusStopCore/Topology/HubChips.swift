import Foundation

/// Folds the chips of a USB hub built from several hub chips into the top
/// chip's `internalParts`, so the map draws one card for the product (SPEC
/// §5.4 "Hub chips"). Runs after `DockParts` on every tree: on the Mac's
/// ports, below docks and displays, and in Other devices.
///
/// A hub folds into its parent hub when it sits on a captive port of that
/// hub (`USBPortType` 1, on both halves of a merged hub): macOS marks a port
/// captive when what is on it cannot be unplugged, so the two chips are one
/// product. Devices that are not hubs never fold, even on a captive port, so
/// a wrong flag can hide at most a hub chip, never something a person
/// plugged in. What hangs off a chip moves up to the top hub, and its
/// `internalParentID` names the chip.
enum HubChips {
    static func fold(_ devices: [DeviceNode], evidence: DockParts.Evidence) -> [DeviceNode] {
        devices.map { fold($0, evidence) }
    }

    private static func fold(_ node: DeviceNode, _ evidence: DockParts.Evidence) -> DeviceNode {
        var node = node
        if DockParts.isHub(node), node.children.contains(where: { isChip($0, evidence) }) {
            node = folding(node, evidence)
        }
        node.children = node.children.map { fold($0, evidence) }
        return node
    }

    /// A hub on a captive port. Its parent must be a hub too.
    static func isChip(_ node: DeviceNode, _ evidence: DockParts.Evidence) -> Bool {
        DockParts.isHub(node) && node.registryID != nil && DockParts.isCaptive(node, evidence)
    }

    /// `hub` with every chip below it folded, down the chain.
    @inline(never)
    private static func folding(_ hub: DeviceNode, _ evidence: DockParts.Evidence) -> DeviceNode {
        var parts: [DeviceNode] = []
        var children: [DeviceNode] = []
        func absorb(_ chip: DeviceNode, parentPartID: String?) {
            var part = chip
            part.children = []
            part.internalParentID = parentPartID
            parts.append(part)
            for child in chip.children {
                if isChip(child, evidence) {
                    absorb(child, parentPartID: chip.id)
                } else {
                    var moved = child
                    moved.internalParentID = chip.id
                    children.append(moved)
                }
            }
        }
        for child in hub.children {
            if isChip(child, evidence) {
                absorb(child, parentPartID: nil)
            } else {
                children.append(child)
            }
        }

        var folded = hub
        folded.children = children
        folded.internalParts = parts.sorted { TopologyBuilder.deviceNameOrder($0.name, $0.id, $1.name, $1.id) }
        return folded
    }
}
