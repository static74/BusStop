// Portions adapted from PortScope (MIT License, © 2026 Alex Zenla).
// The adapted part is the rule that a lane adapter is live only with a peer,
// a non-empty Hop Table or a Link Bandwidth above the idle default of 100.

import Foundation

/// What the Thunderbolt / USB4 switch capture says about each physical socket.
struct ThunderboltTopology {
    /// Socket ID (= USB-C `PortNumber`) → the best live link on the host's
    /// lane adapters for that socket.
    var liveLinks: [Int: LinkInfo] = [:]
    /// Socket ID → the best decodable link whether or not a peer was seen.
    /// Used only when the port itself says CIO is active.
    var decodedLinks: [Int: LinkInfo] = [:]
    /// Socket ID → device chains hanging off that socket (depth-1 switches
    /// with everything daisy-chained behind them).
    var chains: [Int: [DeviceNode]] = [:]
    /// Chains that could not be tied to a socket.
    var unattributedChains: [DeviceNode] = []
    /// `acioN` index → socket IDs of the host-root switch under `acioN`.
    var socketsByACIO: [Int: [Int]] = [:]
    /// Every socket ID published by a host-root lane adapter.
    var allSockets: Set<Int> = []
    /// Registry IDs of downstream switches with a live USB tunnel (a USB
    /// adapter whose `Hop Table` is not empty).
    var usbTunnelSwitchIDs: Set<UInt64> = []
    /// Registry IDs of downstream switches known to carry no display: they
    /// list their adapters, and every DisplayPort / HDMI adapter among them
    /// reports an empty `Hop Table`.
    var noVideoSwitchIDs: Set<UInt64> = []

    /// The socket a USB device tunnelled through `apciecN` arrived on: the
    /// host root under `acioN` (same N). With several sockets on that host,
    /// the only one with a live link is used; otherwise nil (fail closed).
    func socket(forPCIeIndex index: Int) -> Int? {
        guard let sockets = socketsByACIO[index], !sockets.isEmpty else { return nil }
        if sockets.count == 1 { return sockets[0] }
        let live = sockets.filter { liveLinks[$0] != nil }
        return live.count == 1 ? live[0] : nil
    }
}

/// Builds Thunderbolt / USB4 chains and host link rates from
/// `RawSnapshot.thunderboltSwitches`.
///
/// A host-root switch has `Depth` 0 (or no depth and no parent). Its lane
/// adapters (`Description` "Thunderbolt Port") carry a `Socket ID` equal to
/// the USB-C port number. Every downstream switch becomes a `DeviceNode`
/// whose link is the hop from its parent.
enum ThunderboltParser {
    static func parse(_ input: [RawThunderboltSwitch], options: BuildOptions) -> ThunderboltTopology {
        var seen = Set<UInt64>()
        let switches = input.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
        let byID = Dictionary(switches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func depth(_ s: RawThunderboltSwitch) -> Int? { s.node.properties.int("Depth") }

        func parentID(_ s: RawThunderboltSwitch) -> UInt64? {
            if depth(s) == 0 { return nil }
            if let parent = s.parentSwitchID, parent != s.id, byID[parent] != nil { return parent }
            return s.ancestry.first { $0.id != s.id && byID[$0.id] != nil }?.id
        }

        func isHostRoot(_ s: RawThunderboltSwitch) -> Bool {
            if let d = depth(s) { return d == 0 }
            return s.parentSwitchID == nil && parentID(s) == nil
        }

        let hosts = switches.filter(isHostRoot)
        let hostIDs = Set(hosts.map(\.id))
        var children: [UInt64: [UInt64]] = [:]
        var orphans: [RawThunderboltSwitch] = []
        for s in switches where !hostIDs.contains(s.id) {
            if let parent = parentID(s) {
                children[parent, default: []].append(s.id)
            } else {
                orphans.append(s)
            }
        }

        // Lane adapters that some downstream switch hangs below.
        let peerPortIDs = Set(switches.flatMap { $0.ancestry.map(\.id) })

        var topology = ThunderboltTopology()
        topology.usbTunnelSwitchIDs = Set(switches.filter { !hostIDs.contains($0.id) && hasLiveUSBAdapter($0) }.map(\.id))
        topology.noVideoSwitchIDs = Set(switches.filter { !hostIDs.contains($0.id) && carriesNoDisplay($0) }.map(\.id))
        for host in hosts {
            let sockets = Set(lanePorts(host).compactMap(socketID)).sorted()
            topology.allSockets.formUnion(sockets)
            if let acio = acioIndex(host.ancestry) {
                topology.socketsByACIO[acio] = Array(Set((topology.socketsByACIO[acio] ?? []) + sockets)).sorted()
            }
        }

        // Builds one switch and everything below it.
        var visited = Set<UInt64>()
        func build(_ id: UInt64, parent: RawThunderboltSwitch?, depthHint: Int) -> DeviceNode? {
            guard visited.insert(id).inserted, let s = byID[id] else { return nil }
            let below = (children[id] ?? []).compactMap { build($0, parent: s, depthHint: depthHint + 1) }
            var node = deviceNode(for: s, parent: parent, depthHint: depthHint, options: options)
            node.children = below
            return node
        }

        // Depth-1 chains under each host root, tied to a socket.
        for host in hosts {
            for childID in children[host.id] ?? [] {
                guard let child = byID[childID], let chain = build(childID, parent: host, depthHint: 1) else { continue }
                if let socket = socket(of: child, on: host) {
                    topology.chains[socket, default: []].append(chain)
                } else {
                    topology.unattributedChains.append(chain)
                }
            }
        }

        // Switches whose parent was not captured: find their host through
        // the shared `acioN` ancestor, or leave them unattributed.
        for orphan in orphans {
            let hint = min(max(depth(orphan) ?? 1, 1), 64)
            guard let chain = build(orphan.id, parent: nil, depthHint: hint) else { continue }
            let host = acioIndex(orphan.ancestry).flatMap { index in
                hosts.first { acioIndex($0.ancestry) == index }
            }
            if let host, let socket = socket(of: orphan, on: host) {
                topology.chains[socket, default: []].append(chain)
            } else {
                topology.unattributedChains.append(chain)
            }
        }

        // Host link per socket. Idle lanes on older controllers still report
        // a 10 Gb/s × 1 link, so a lane counts as live only with a peer: a
        // switch below it, a chain on its socket, a non-empty `Hop Table`, or
        // `Link Bandwidth` above the idle default of 100.
        for host in hosts {
            for lane in lanePorts(host) {
                guard let socket = socketID(lane),
                      let link = LinkDecoding.thunderboltLink(lanePort: lane.properties) else { continue }
                topology.decodedLinks[socket] = LinkDecoding.faster(topology.decodedLinks[socket], link)
                let hasPeer = peerPortIDs.contains(lane.id)
                    || !(topology.chains[socket] ?? []).isEmpty
                    || TopologyValues.isEmpty(lane.properties["Hop Table"]) == false
                    || (lane.properties.int("Link Bandwidth") ?? 0) > 100
                if hasPeer {
                    topology.liveLinks[socket] = LinkDecoding.faster(topology.liveLinks[socket], link)
                }
            }
        }
        return topology
    }

    // MARK: - Pieces

    /// Lane adapters of a switch: `Description` "Thunderbolt Port", or any
    /// adapter that publishes a `Socket ID`. Sorted by registry ID.
    static func lanePorts(_ s: RawThunderboltSwitch) -> [RawNode] {
        s.ports.filter { port in
            port.properties.string("Description") == "Thunderbolt Port" || port.properties.has("Socket ID")
        }.sorted { $0.id < $1.id }
    }

    /// `Socket ID` as a positive port number (it is published as a string).
    static func socketID(_ lane: RawNode) -> Int? {
        guard let value = lane.properties.int("Socket ID"), value > 0, value < 1000 else { return nil }
        return value
    }

    /// N of the nearest `acioN` ancestor.
    static func acioIndex(_ ancestry: [RawAncestor]) -> Int? {
        ancestry.lazy.compactMap { TopologyText.indexedName($0.name, prefix: "acio") }.first
    }

    /// The socket a switch hangs off on a host root: the host lane adapter in
    /// its ancestry, else the host's only socket, else the only socket with a
    /// lane that looks live.
    static func socket(of child: RawThunderboltSwitch, on host: RawThunderboltSwitch) -> Int? {
        let lanes = lanePorts(host)
        let laneIDs = Set(lanes.map(\.id))
        if let entry = child.ancestry.first(where: { laneIDs.contains($0.id) }),
           let lane = lanes.first(where: { $0.id == entry.id }), let socket = socketID(lane) {
            return socket
        }
        let sockets = Set(lanes.compactMap(socketID)).sorted()
        if sockets.count == 1 { return sockets[0] }
        let live = Set(lanes.filter { lane in
            LinkDecoding.thunderboltLink(lanePort: lane.properties) != nil
                && (TopologyValues.isEmpty(lane.properties["Hop Table"]) == false
                    || (lane.properties.int("Link Bandwidth") ?? 0) > 100)
        }.compactMap(socketID)).sorted()
        return live.count == 1 ? live[0] : nil
    }

    /// The link between a switch and its parent: the parent's adapter that
    /// appears first in the switch's ancestry, else the switch's own upstream
    /// adapter (`Upstream Port Number`).
    static func hopLink(child: RawThunderboltSwitch, parent: RawThunderboltSwitch?) -> LinkInfo? {
        if let parent {
            let parentPorts = Dictionary(parent.ports.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            if let entry = child.ancestry.first(where: { parentPorts[$0.id] != nil }),
               let port = parentPorts[entry.id],
               let link = LinkDecoding.thunderboltLink(lanePort: port.properties) {
                return link
            }
        }
        if let upstream = child.node.properties.int("Upstream Port Number"),
           let port = child.ports.sorted(by: { $0.id < $1.id })
               .first(where: { $0.properties.int("Port Number") == upstream }) {
            return LinkDecoding.thunderboltLink(lanePort: port.properties)
        }
        return nil
    }

    /// The model name with a repeated vendor prefix removed: "Ugreen Ugreen
    /// Revodok" → "Ugreen Revodok", and with vendor "Other World Computing",
    /// "Other World Computing Other World Computing Envoy" → "Other World
    /// Computing Envoy".
    static func modelName(_ raw: String?, vendor: String? = nil) -> String? {
        guard let cleaned = TopologyText.clean(raw) else { return nil }
        var words = cleaned.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if let vendor = TopologyText.clean(vendor) {
            let prefix = vendor.split(separator: " ", omittingEmptySubsequences: true).map { $0.lowercased() }
            let n = prefix.count
            while n > 0, words.count > 2 * n,
                  words[0..<n].map({ $0.lowercased() }) == prefix,
                  words[n..<(2 * n)].map({ $0.lowercased() }) == prefix {
                words.removeFirst(n)
            }
        }
        while words.count >= 2, words[0].lowercased() == words[1].lowercased() {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    /// A USB adapter carrying a live tunnel.
    static func hasLiveUSBAdapter(_ s: RawThunderboltSwitch) -> Bool {
        s.ports.contains { port in
            let description = port.properties.string("Description")?.lowercased() ?? ""
            return description.contains("usb") && TopologyValues.isEmpty(port.properties["Hop Table"]) == false
        }
    }

    /// True for DisplayPort / HDMI adapters (`"DP or HDMI Adapter"`).
    static func isDisplayAdapter(_ port: RawNode) -> Bool {
        let description = port.properties.string("Description")?.lowercased() ?? ""
        return description.contains("dp") || description.contains("hdmi")
    }

    /// True when the switch is known to carry no display tunnel: it lists
    /// its adapters (at least one has a `Description`), and every display
    /// adapter publishes a `Hop Table` that is empty. A missing `Hop Table`
    /// leaves the question open, so the answer is false.
    static func carriesNoDisplay(_ s: RawThunderboltSwitch) -> Bool {
        guard s.ports.contains(where: { $0.properties.string("Description") != nil }) else { return false }
        return s.ports.filter(isDisplayAdapter).allSatisfy { TopologyValues.isEmpty($0.properties["Hop Table"]) == true }
    }

    /// Display, dock or generic Thunderbolt device, from the name and the
    /// switch's protocol adapters.
    static func kind(for s: RawThunderboltSwitch, name: String) -> DeviceKind {
        let words = TopologyText.words(name)
        let descriptions = s.ports.map { $0.properties.string("Description")?.lowercased() ?? "" }
        let hasDataAdapters = descriptions.contains { $0.contains("usb") || $0.contains("pcie") }
        let hasLiveDisplayAdapter = s.ports.contains { port in
            let description = port.properties.string("Description")?.lowercased() ?? ""
            return (description.contains("dp") || description.contains("hdmi"))
                && TopologyValues.isEmpty(port.properties["Hop Table"]) == false
        }
        if DeviceClassifier.has(words, "display", "monitor") { return .display }
        if hasDataAdapters, DeviceClassifier.has(words, "dock", "docking", "hub", "station") { return .dock }
        if hasLiveDisplayAdapter { return .display }
        return .thunderboltDevice
    }

    /// `"tb:<UID hex>"`, or the registry ID when the switch has no UID.
    static func deviceID(for s: RawThunderboltSwitch) -> String {
        if let uid = s.node.properties.int64("UID") {
            return "tb:" + TopologyText.hex(UInt64(bitPattern: uid), width: 16)
        }
        return "tb:reg-" + TopologyText.hex(s.id, width: 1)
    }

    static func deviceNode(for s: RawThunderboltSwitch, parent: RawThunderboltSwitch?, depthHint: Int,
                           options: BuildOptions) -> DeviceNode {
        let p = s.node.properties
        let vendor = TopologyText.clean(p.string("Device Vendor Name"))
        let name = modelName(p.string("Device Model Name"), vendor: vendor)
            ?? vendor.map { "\($0) Thunderbolt Device" }
            ?? "Thunderbolt Device"
        var depth = p.int("Depth") ?? depthHint
        if depth < 1 || depth > 64 { depth = depthHint }
        return DeviceNode(id: deviceID(for: s), registryID: s.id, bus: .thunderbolt, kind: kind(for: s, name: name),
                          name: name, vendorName: vendor, vendorID: p.int("Vendor ID"), productID: p.int("Device ID"),
                          link: hopLink(child: s, parent: parent), isTunneled: false, chainDepth: depth,
                          properties: options.includeRawProperties ? p.withoutPlumbing() : nil)
    }
}
