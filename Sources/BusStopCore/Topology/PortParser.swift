import Foundation

/// One physical port while the builder works on it.
struct TopologyPortRecord {
    /// The node chosen to represent the port (several nodes can share a key).
    let node: RawNode
    let key: PortKey
    let kind: PortKind
    let number: Int
    /// `"Port-USB-C@1"`.
    let registryName: String
    /// Every captured node that resolved to this port.
    let nodeIDs: Set<UInt64>

    var properties: PropertyBag { node.properties }

    /// `TransportsSupported` minus CC; nil when the key is missing.
    var supportedTransports: [TransportKind]? {
        guard let names = properties.strings("TransportsSupported") else { return nil }
        return Self.kinds(names).filter { $0 != .cc }
    }

    /// `TransportsActive` minus CC; nil when the key is missing. This is the
    /// authoritative list of live transports (`IOAccessoryUSBSuperSpeedActive`
    /// goes stale and is ignored).
    var listedActiveTransports: Set<TransportKind>? {
        guard let names = properties.strings("TransportsActive") else { return nil }
        return Set(Self.kinds(names).filter { $0 != .cc })
    }

    /// `ConnectionActive`, or hot-plug detect (`HDMI_HPD`) on an HDMI port.
    var connectionActive: Bool {
        properties.bool("ConnectionActive") == true || (kind == .hdmi && properties.bool("HDMI_HPD") == true)
    }

    /// Sorted, de-duplicated transport kinds from IOKit names.
    static func kinds(_ names: [String]) -> [TransportKind] {
        Array(Set(names.compactMap(TransportKind.init(ioKitName:)))).sorted()
    }
}

/// The ports of one capture with the lookups the other parsers need.
struct TopologyPortTable {
    /// Ports sorted by key.
    let records: [TopologyPortRecord]
    private let byKey: [PortKey: Int]
    private let byNodeID: [UInt64: PortKey]

    init(records: [TopologyPortRecord]) {
        let sorted = records.sorted { $0.key < $1.key }
        self.records = sorted
        var keys: [PortKey: Int] = [:]
        var nodes: [UInt64: PortKey] = [:]
        for (offset, record) in sorted.enumerated() {
            keys[record.key] = offset
            for id in record.nodeIDs { nodes[id] = record.key }
        }
        byKey = keys
        byNodeID = nodes
    }

    var isEmpty: Bool { records.isEmpty }
    var keys: [PortKey] { records.map(\.key) }

    func record(_ key: PortKey) -> TopologyPortRecord? {
        byKey[key].map { records[$0] }
    }

    func key(forNodeID id: UInt64) -> PortKey? { byNodeID[id] }

    /// The port with a connector kind and number. USB-C and Thunderbolt are
    /// the same receptacle. With an unknown kind the number alone must be
    /// unique.
    func key(kind: PortKind, number: Int) -> PortKey? {
        let sameKind: (PortKind) -> Bool = { candidate in
            if candidate == kind { return true }
            let usbC: Set<PortKind> = [.usbC, .thunderbolt]
            return usbC.contains(candidate) && usbC.contains(kind)
        }
        if kind != .unknown, let match = records.first(where: { sameKind($0.kind) && $0.number == number }) {
            return match.key
        }
        if kind == .unknown {
            let matches = records.filter { $0.number == number }
            if matches.count == 1 { return matches[0].key }
        }
        return nil
    }

    /// The USB-C port with a number (Thunderbolt `Socket ID`, `usb-drdN`
    /// `port-number`, `PowerOutDetails.PortIndex`). Falls back to the only
    /// port of any kind with that number.
    func usbCKey(number: Int) -> PortKey? {
        if let key = key(kind: .usbC, number: number) { return key }
        let matches = records.filter { $0.number == number && $0.kind != .magSafe }
        return matches.count == 1 ? matches[0].key : nil
    }

    /// The port named by a registry path component such as `"Port-USB-C@2"`:
    /// an exact registry-name match first, then connector kind and number.
    func key(registryComponent component: String) -> PortKey? {
        let trimmed = component.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
        if let match = records.first(where: { $0.registryName == trimmed }) { return match.key }
        guard let parsed = TopologyText.parsePortComponent(trimmed) else { return nil }
        let kind = PortKind(portType: nil, description: parsed.typeText)
        return key(kind: kind, number: parsed.number)
    }

    /// The port a feature, transport or component node belongs to: the
    /// `parentID` chain first, then `ParentPortType` / `ParentPortNumber`
    /// (or the `ParentBuiltIn…` pair), then the description path prefix
    /// (`"Port-USB-C@2/USB3"`).
    func owner(of node: RawNode, index: TopologyNodeIndex) -> PortKey? {
        if let key = byNodeID[node.id] { return key }
        if let parent = node.parentID, let key = byNodeID[parent] { return key }
        for ancestor in index.ancestors(of: node) {
            if let key = byNodeID[ancestor.id] { return key }
        }
        let p = node.properties
        for (typeKey, numberKey) in [("ParentPortType", "ParentPortNumber"),
                                     ("ParentBuiltInPortType", "ParentBuiltInPortNumber")] {
            if let type = p.int(typeKey), let number = p.int(numberKey), byKey[PortKey(type: type, number: number)] != nil {
                return PortKey(type: type, number: number)
            }
        }
        for descriptionKey in ["TransportDescription", "Description", "ParentTransportTypeDescription",
                               "ParentComponentDescription"] {
            if let path = p.string(descriptionKey), let first = TopologyText.firstPathComponent(path),
               let key = key(registryComponent: first) {
                return key
            }
        }
        return nil
    }
}

/// Finds the physical ports among the captured port-controller nodes.
enum PortParser {
    /// A node is a physical port when it has `PortTypeDescription` and
    /// `PortNumber`, has no `ParentPortType` (transports and features carry
    /// one), and is not marked `BuiltIn = No` (inductive and virtual ports).
    static func isPortNode(_ node: RawNode) -> Bool {
        if TopologyClass.has(node, prefix: "IOPortTransport") || TopologyClass.has(node, prefix: "IOPortFeature") {
            return false
        }
        let p = node.properties
        guard let description = p.string("PortTypeDescription"), p.int("PortNumber") != nil else { return false }
        if p.has("ParentPortType") || p.has("ParentBuiltInPortType") { return false }
        if p.bool("BuiltIn") == false { return false }
        let lowered = description.lowercased()
        if lowered.hasPrefix("inductive") || lowered.hasPrefix("virtual") { return false }
        return true
    }

    /// Connector kind from `PortType` and `PortTypeDescription`.
    static func kind(of node: RawNode) -> PortKind {
        PortKind(portType: node.properties.int("PortType"), description: node.properties.string("PortTypeDescription"))
    }

    /// The `PortType` code used in a port key. Nodes without one (bare USB-A
    /// `IOPort` nodes, for example) get the conventional code for their kind,
    /// or `PortKey.unknownType`.
    static func portType(for node: RawNode, kind: PortKind) -> Int {
        if let type = node.properties.int("PortType") { return type }
        switch kind {
        case .usbA: return PortKey.usbAType
        case .usbC, .thunderbolt: return PortKey.usbCType
        case .magSafe: return PortKey.magSafeType
        case .hdmi: return PortKey.hdmiType
        case .sdCard, .unknown: return PortKey.unknownType
        }
    }

    /// Builds the port table. When several nodes share a key, the one with
    /// the most properties (then the lowest registry ID) represents it.
    static func parse(_ index: TopologyNodeIndex) -> TopologyPortTable {
        var groups: [PortKey: [RawNode]] = [:]
        for node in index.nodes where isPortNode(node) {
            let p = node.properties
            guard let number = p.int("PortNumber") else { continue }
            let key = PortKey(type: portType(for: node, kind: kind(of: node)), number: number)
            groups[key, default: []].append(node)
        }

        var records: [TopologyPortRecord] = []
        for key in groups.keys.sorted() {
            guard let nodes = groups[key] else { continue }
            let chosen = nodes.sorted { lhs, rhs in
                if lhs.properties.values.count != rhs.properties.values.count {
                    return lhs.properties.values.count > rhs.properties.values.count
                }
                return lhs.id < rhs.id
            }
            guard let node = chosen.first else { continue }
            let kind = kind(of: node)
            let p = node.properties
            let registryName = p.string(["PortDescription", "Description"]) ?? node.registryPathComponent
            records.append(TopologyPortRecord(node: node, key: key, kind: kind, number: key.number,
                                              registryName: registryName, nodeIDs: Set(nodes.map(\.id))))
        }
        return TopologyPortTable(records: records)
    }

    /// Lifetime counters, or nil when the port publishes none.
    static func statistics(_ record: TopologyPortRecord) -> PortStatistics? {
        let p = record.properties
        let stats = PortStatistics(connectionCount: p.int("ConnectionCount"),
                                   plugEventCount: p.int("Plug Event Count"),
                                   overcurrentCount: p.int("Overcurrent Count"))
        if stats.connectionCount == nil, stats.plugEventCount == nil, stats.overcurrentCount == nil { return nil }
        return stats
    }
}
