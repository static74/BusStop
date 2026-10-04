import BusStopCore
import Foundation
import IOKit

/// Reads port controllers and everything below them: the `IOPort` registry
/// plane (macOS 26+) merged with services matched by class in the `IOService`
/// plane, de-duplicated by registry ID.
enum PortNodeReader {
    /// Classes matched in the `IOService` plane. Classes that do not exist on
    /// a given Mac simply match nothing.
    static let serviceClasses = [
        "IOAccessoryManager", "IOPort", "AppleHDMIPortController",
        "IOPortTransportStateCC", "IOPortTransportStateUSB2", "IOPortTransportStateUSB3",
        "IOPortTransportStateDisplayPort", "IOPortTransportStateCIO",
        "IOPortFeaturePowerIn", "IOPortFeaturePowerSource",
        "IOPortTransportComponentCCUSBPDSOP", "IOPortTransportComponentCCUSBPDSOPp",
        "IOPortTransportComponentCCUSBPDSOPpp",
        "IOPortTransportProtocolAppleUVDM", "AppleHPMLDCMType2",
    ]

    /// Deepest `IOPort`-plane level visited below the root.
    static let maxPlaneDepth = 16
    /// `IOService`-plane ancestors examined when placing a class-matched node.
    static let maxServiceAncestors = 16
    /// `IOService`-plane ancestors searched for the HPM controller `UUID`.
    static let maxUUIDAncestors = 4

    struct Result {
        var nodes: [RawNode]
        var controllerUUIDs: [String: String]
    }

    static func read(rootID: UInt64?, notes: inout [String]) -> Result {
        var collector = Collector()
        if let root = RegistryEntry.root() {
            if planeExists(RegistryPlane.port, root: root) {
                walkPortPlane(below: root, parentID: nil, depth: 0, into: &collector)
            } else {
                notes.append("IOPort registry plane not present; using class matching only")
            }
        } else {
            notes.append("IORegistry root entry unavailable")
        }
        for className in serviceClasses {
            for entry in RegistryEntry.matching(className: className) {
                collector.addServiceNode(entry, rootID: rootID)
            }
        }
        return collector.finish()
    }

    /// Whether the registry publishes `plane` (root `IORegistryPlanes`).
    static func planeExists(_ plane: String, root: RegistryEntry) -> Bool {
        root.property("IORegistryPlanes")?.dictValue?[plane] != nil
    }

    private static func walkPortPlane(below entry: RegistryEntry, parentID: UInt64?, depth: Int,
                                      into collector: inout Collector) {
        guard depth < maxPlaneDepth else { return }
        for child in entry.children(in: RegistryPlane.port) {
            guard let id = child.entryID, !collector.contains(id) else { continue }
            // USB devices are captured with their own ancestry in `usbDevices`.
            if child.conforms(to: "IOUSBHostDevice") { continue }
            guard collector.add(child, id: id, parentID: parentID) else { continue }
            walkPortPlane(below: child, parentID: id, depth: depth + 1, into: &collector)
        }
    }

    // MARK: Node reading

    /// How a node's properties are read.
    enum Family: Equatable {
        /// Long-lived port controller: one bulk read.
        case controller
        case transportCC, transportUSB, transportDisplayPort, transportCIO
        case feature, component, transportProtocol
        /// Unrecognised class: per-key read of every known child key.
        case other
    }

    /// The family of the nearest recognised class in `chain` (class first,
    /// then superclasses).
    static func family(of chain: [String]) -> Family {
        for name in chain {
            if name.hasPrefix("IOPortTransportStateCC") { return .transportCC }
            if name.hasPrefix("IOPortTransportStateUSB") { return .transportUSB }
            if name.hasPrefix("IOPortTransportStateDisplayPort") { return .transportDisplayPort }
            if name.hasPrefix("IOPortTransportStateCIO") { return .transportCIO }
            if name.hasPrefix("IOPortTransportState") { return .other }
            if name.hasPrefix("IOPortFeature") || name.hasPrefix("AppleHPMLDCM") { return .feature }
            if name.hasPrefix("IOPortTransportComponent") { return .component }
            if name.hasPrefix("IOPortTransportProtocol") { return .transportProtocol }
            if name == "IOAccessoryManager" || name == "AppleHDMIPortController" || name == "IOPort" {
                return .controller
            }
        }
        return .other
    }

    /// Reads a node's properties: bulk for port controllers, per key for
    /// volatile transport, feature and PD nodes.
    static func properties(of entry: RegistryEntry, family: Family) -> [String: PlistValue] {
        let common = RegistryKeys.portChildCommon
        switch family {
        case .controller:
            let values = entry.allProperties() ?? entry.properties(keys: RegistryKeys.portController)
            return RegistryKeys.cleaned(values)
        case .transportCC:
            return entry.properties(keys: common)
        case .transportUSB:
            return entry.properties(keys: common + RegistryKeys.usbTransport)
        case .transportDisplayPort:
            return entry.properties(keys: common + RegistryKeys.displayPortTransport)
        case .transportCIO:
            return entry.properties(keys: common + RegistryKeys.cioTransport)
        case .feature:
            return entry.properties(keys: common + RegistryKeys.feature)
        case .component:
            return entry.properties(keys: common + RegistryKeys.component)
        case .transportProtocol:
            return entry.properties(keys: common + RegistryKeys.transportProtocol)
        case .other:
            return entry.properties(keys: RegistryKeys.anyPortChild)
        }
    }

    /// The `UUID` of the HPM controller (`AppleHPMDevice*`) above a port,
    /// searched up to `maxUUIDAncestors` levels in the `IOService` plane.
    static func controllerUUID(of entry: RegistryEntry) -> String? {
        var current = entry.parent(in: RegistryPlane.service)
        var level = 0
        while let ancestor = current, level < maxUUIDAncestors {
            if let className = ancestor.className, isHPMDevice(className) {
                guard let uuid = ancestor.property("UUID")?.stringValue, !uuid.isEmpty else { return nil }
                return uuid
            }
            current = ancestor.parent(in: RegistryPlane.service)
            level += 1
        }
        return nil
    }

    private static func isHPMDevice(_ className: String) -> Bool {
        className.hasPrefix("AppleHPMDevice") || ClassHierarchy.chain(for: className).contains("AppleHPMDevice")
    }

    // MARK: Collector

    /// Accumulates nodes from both walks and resolves parents at the end.
    struct Collector {
        private(set) var nodes: [RawNode] = []
        private var indexByID: [UInt64: Int] = [:]
        /// `IOService`-plane ancestor IDs (nearest first) of nodes found only
        /// by class matching.
        private var serviceAncestors: [UInt64: [UInt64]] = [:]
        private var uuids: [String: String] = [:]

        func contains(_ id: UInt64) -> Bool { indexByID[id] != nil }

        /// Records one node. Returns false when the entry cannot be identified.
        @discardableResult
        mutating func add(_ entry: RegistryEntry, id: UInt64, parentID: UInt64?) -> Bool {
            guard indexByID[id] == nil, let className = entry.className else { return false }
            let chain = ClassHierarchy.chain(for: className)
            let values = PortNodeReader.properties(of: entry, family: PortNodeReader.family(of: chain))
            let bag = PropertyBag(values)
            let node = RawNode(
                id: id,
                parentID: parentID,
                className: className,
                classChain: chain,
                name: entry.name ?? className,
                location: entry.location(inFirstOf: [RegistryPlane.service, RegistryPlane.port]),
                properties: bag
            )
            indexByID[id] = nodes.count
            nodes.append(node)
            recordControllerUUID(for: entry, properties: bag)
            return true
        }

        /// Records a node found by class matching, remembering its
        /// `IOService`-plane ancestors so its parent can be resolved later.
        mutating func addServiceNode(_ entry: RegistryEntry, rootID: UInt64?) {
            guard let id = entry.entryID, indexByID[id] == nil else { return }
            guard add(entry, id: id, parentID: nil) else { return }
            var ancestors: [UInt64] = []
            var current = entry.parent(in: RegistryPlane.service)
            var level = 0
            while let ancestor = current, level < PortNodeReader.maxServiceAncestors {
                level += 1
                if let ancestorID = ancestor.entryID, ancestorID != rootID {
                    ancestors.append(ancestorID)
                }
                current = ancestor.parent(in: RegistryPlane.service)
            }
            serviceAncestors[id] = ancestors
        }

        private mutating func recordControllerUUID(for entry: RegistryEntry, properties: PropertyBag) {
            guard properties.has("PortNumber"), !properties.has("ParentPortType"),
                  let type = properties.int("PortType"), let number = properties.int("PortNumber") else { return }
            let key = "\(type)/\(number)"
            guard uuids[key] == nil, let uuid = PortNodeReader.controllerUUID(of: entry) else { return }
            uuids[key] = uuid
        }

        /// Sets each class-matched node's parent to its nearest captured
        /// `IOService`-plane ancestor.
        func finish() -> Result {
            var result = nodes
            for (id, ancestors) in serviceAncestors {
                guard let index = indexByID[id] else { continue }
                result[index].parentID = ancestors.first { $0 != id && indexByID[$0] != nil }
            }
            return Result(nodes: result, controllerUUIDs: uuids)
        }
    }
}
