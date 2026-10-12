import BusStopCore
import Foundation
import IOKit

/// Reads Thunderbolt / USB4 switches (`IOThunderboltSwitch*`, and the
/// `IOIOThunderboltSwitch*` spelling some builds use) with their port
/// children, ancestry and upstream switch.
enum ThunderboltReader {
    static let switchClasses = ["IOThunderboltSwitch", "IOIOThunderboltSwitch"]
    static let portClasses = ["IOThunderboltPort", "IOIOThunderboltPort"]
    /// `IOService`-plane ancestors recorded per switch.
    static let maxAncestors = 40

    static func read() -> [RawThunderboltSwitch] {
        var switches: [RawThunderboltSwitch] = []
        var seen = Set<UInt64>()
        for className in switchClasses {
            for entry in RegistryEntry.matching(className: className) {
                guard let id = entry.entryID, seen.insert(id).inserted, let switchClass = entry.className else {
                    continue
                }
                switches.append(readSwitch(entry, id: id, className: switchClass))
            }
        }
        return switches
    }

    private static func readSwitch(_ entry: RegistryEntry, id: UInt64, className: String) -> RawThunderboltSwitch {
        let node = RawNode(
            id: id,
            className: className,
            classChain: ClassHierarchy.chain(for: className),
            name: entry.name ?? className,
            location: entry.location(in: RegistryPlane.service),
            properties: PropertyBag(entry.properties(keys: RegistryKeys.thunderboltSwitch))
        )

        var ports: [RawNode] = []
        for child in entry.children(in: RegistryPlane.service) {
            guard portClasses.contains(where: { child.conforms(to: $0) }),
                  let portID = child.entryID, let portClass = child.className else { continue }
            ports.append(RawNode(
                id: portID,
                parentID: id,
                className: portClass,
                classChain: ClassHierarchy.chain(for: portClass),
                name: child.name ?? portClass,
                location: child.location(in: RegistryPlane.service),
                properties: PropertyBag(child.properties(keys: RegistryKeys.thunderboltPort))
            ))
        }

        var ancestry: [RawAncestor] = []
        var parentSwitchID: UInt64?
        var current = entry.parent(in: RegistryPlane.service)
        while let ancestor = current, ancestry.count < maxAncestors {
            let ancestorID = ancestor.entryID ?? 0
            ancestry.append(RawAncestor(
                id: ancestorID,
                className: ancestor.className ?? "",
                name: ancestor.name ?? "",
                location: ancestor.location(in: RegistryPlane.service)
            ))
            if parentSwitchID == nil, switchClasses.contains(where: { ancestor.conforms(to: $0) }) {
                parentSwitchID = ancestorID
            }
            current = ancestor.parent(in: RegistryPlane.service)
        }

        return RawThunderboltSwitch(node: node, parentSwitchID: parentSwitchID, ports: ports, ancestry: ancestry)
    }
}
