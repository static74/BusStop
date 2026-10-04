import Foundation

/// What the USB builder needs from the port, transport and Thunderbolt parsers.
struct USBAttributionContext {
    let ports: TopologyPortTable
    let index: TopologyNodeIndex
    /// Transport node registry ID → its port.
    let transportPorts: [UInt64: PortKey]
    let thunderbolt: ThunderboltTopology
    /// Ports whose own CIO transport is active, sorted.
    let cioActivePorts: [PortKey]

    /// The port an `IOPort`-plane node belongs to, by registry ID.
    func portKey(forNodeID id: UInt64) -> PortKey? {
        if let key = transportPorts[id] ?? ports.key(forNodeID: id) { return key }
        return index.byID[id].flatMap { ports.owner(of: $0, index: index) }
    }
}

/// USB device trees grouped by the physical port they hang off.
struct USBForest {
    var byPort: [PortKey: [DeviceNode]] = [:]
    var unattributed: [DeviceNode] = []
}

/// Builds USB device trees from `RawSnapshot.usbDevices` and ties each tree
/// to a physical port (SPEC §5.4 "USB device attribution").
enum USBTreeBuilder {
    static func build(_ input: [RawUSBDevice], context: USBAttributionContext, options: BuildOptions) -> USBForest {
        var seen = Set<UInt64>()
        let devices = input.filter { seen.insert($0.id).inserted }.sorted { $0.id < $1.id }
        let byID = Dictionary(devices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func parentID(_ d: RawUSBDevice) -> UInt64? {
            guard let parent = d.parentDeviceID, parent != d.id, byID[parent] != nil else { return nil }
            return parent
        }

        // Devices behind the internal controller (camera, SoC) are dropped
        // with everything below them.
        var excluded = Set<UInt64>()
        for device in devices {
            var current: RawUSBDevice? = device
            var steps = 0
            var visited = Set<UInt64>()
            while let d = current, steps < 64, visited.insert(d.id).inserted {
                if isBehindInternalController(d.ancestry) { excluded.insert(device.id); break }
                current = parentID(d).flatMap { byID[$0] }
                steps += 1
            }
        }

        var children: [UInt64: [UInt64]] = [:]
        var roots: [UInt64] = []
        for device in devices where !excluded.contains(device.id) {
            if let parent = parentID(device), !excluded.contains(parent) {
                children[parent, default: []].append(device.id)
            } else {
                roots.append(device.id)
            }
        }

        // Builds a device and its subtree, once each, even if the capture
        // contains a parent cycle.
        var placed = Set<UInt64>()
        func makeTree(_ id: UInt64, inheritedTunnel: Bool) -> DeviceNode? {
            guard placed.insert(id).inserted, let device = byID[id] else { return nil }
            var node = makeNode(device, options: options)
            node.isTunneled = node.isTunneled || inheritedTunnel
            node.children = (children[id] ?? []).compactMap { makeTree($0, inheritedTunnel: node.isTunneled) }
            node.kind = DeviceClassifier.refineHub(node)
            return node
        }

        var forest = USBForest()
        var pending = roots
        var remaining = Set(devices.map(\.id)).subtracting(excluded)
        while true {
            for id in pending {
                guard let device = byID[id], let tree = makeTree(id, inheritedTunnel: false) else { continue }
                if let key = attribute(device, context: context) {
                    forest.byPort[key, default: []].append(tree)
                } else {
                    forest.unattributed.append(contentsOf: filterInternal(tree) { node in
                        node.registryID.flatMap { byID[$0]?.node.properties.int("USBPortType") }
                    })
                }
            }
            remaining.subtract(placed)
            // Anything left sits in a parent cycle; start again from its lowest ID.
            guard let next = remaining.min() else { break }
            pending = [next]
        }

        for key in forest.byPort.keys.sorted() {
            forest.byPort[key] = mergeCompanionHubs(forest.byPort[key] ?? [])
        }
        forest.unattributed = mergeCompanionHubs(forest.unattributed)
        return forest
    }

    // MARK: - Attribution

    /// The physical port a root device hangs off, most reliable source first:
    /// `UsbIOPort` path, `IOPort`-plane transport parent, Thunderbolt tunnel
    /// (`apciecN` ↔ `acioN` ↔ `Socket ID`), `usb-drdN` `port-number`.
    static func attribute(_ device: RawUSBDevice, context: USBAttributionContext) -> PortKey? {
        if let path = device.usbIOPortPath, let last = TopologyText.lastPathComponent(path),
           let key = context.ports.key(registryComponent: last) {
            return key
        }
        if let parent = device.ioPortParentID, let key = context.portKey(forNodeID: parent) {
            return key
        }
        if hasTunnelAncestry(device.ancestry) {
            if let index = pcieIndex(device.ancestry), let socket = context.thunderbolt.socket(forPCIeIndex: index),
               let key = context.ports.usbCKey(number: socket) {
                return key
            }
            if context.cioActivePorts.count == 1 { return context.cioActivePorts[0] }
        }
        if let number = device.drdPortNumber, let key = context.ports.usbCKey(number: number) {
            return key
        }
        return nil
    }

    /// N of the nearest `apciecN` ancestor (the PCIe root of a Thunderbolt tunnel).
    static func pcieIndex(_ ancestry: [RawAncestor]) -> Int? {
        ancestry.lazy.compactMap { TopologyText.indexedName($0.name, prefix: "apciec") }.first
    }

    /// True when the device reached the Mac through a Thunderbolt / USB4
    /// tunnel: its controller is `AppleUSBXHCITR*`, a known dock xHCI, or
    /// another non-Apple xHCI below an `apciecN` root.
    static func hasTunnelAncestry(_ ancestry: [RawAncestor]) -> Bool {
        for (offset, ancestor) in ancestry.enumerated() {
            if ancestor.className.hasPrefix("AppleUSBXHCITR") || ancestor.name.hasPrefix("AppleUSBXHCITR") { return true }
            if isKnownDockController(ancestor.className) { return true }
            if isOtherXHCI(ancestor.className),
               ancestry[(offset + 1)...].contains(where: { TopologyText.indexedName($0.name, prefix: "apciec") != nil }) {
                return true
            }
        }
        return false
    }

    /// xHCI drivers that docks and displays bring along (TB3 docks, LG UltraFine).
    static func isKnownDockController(_ className: String) -> Bool {
        className.hasPrefix("AppleUSBXHCIFL1100") || className.hasPrefix("AppleASMediaUSBXHCI")
            || className == "AppleUSBXHCIAR"
    }

    /// An xHCI class that is neither the Mac's own controller (`AppleT…`),
    /// a board-mounted one (`AppleEmbedded…`), an Intel one nor the internal
    /// `AUSS` controller.
    static func isOtherXHCI(_ className: String) -> Bool {
        className.contains("XHCI") && !className.hasPrefix("AppleT") && !className.hasPrefix("AppleEmbedded")
            && !className.hasPrefix("AppleIntel") && !className.contains("AUSS")
    }

    /// Behind `usb-auss` / `AppleUSBXHCIAUSS`: the internal camera and SoC bus.
    static func isBehindInternalController(_ ancestry: [RawAncestor]) -> Bool {
        ancestry.contains { $0.name.hasPrefix("usb-auss") || $0.className.contains("AUSS") }
    }

    // MARK: - Internal devices

    /// Unattributed Apple-internal devices are dropped. Internal hubs are
    /// removed but their children are kept (and checked in turn), so an
    /// external device behind an internal hub still shows up.
    /// `portType` reads `USBPortType` (2 = internal) for a node.
    static func filterInternal(_ tree: DeviceNode, portType: (DeviceNode) -> Int?) -> [DeviceNode] {
        let isInternal = portType(tree) == 2 || isAppleInternalName(tree)
        guard isInternal else { return [tree] }
        if tree.deviceClass == DeviceClassifier.USBClass.hub || tree.kind == .hub {
            return tree.children.flatMap { filterInternal($0, portType: portType) }
        }
        return []
    }

    /// Apple-vendor devices named like built-in hardware.
    static func isAppleInternalName(_ node: DeviceNode) -> Bool {
        guard node.vendorID == DeviceClassifier.appleVendorID else { return false }
        let lowered = node.name.lowercased()
        let phrases = ["internal", "facetime", "touch bar", "keyboard / trackpad", "ambient light", "ibridge", "bluetooth"]
        if phrases.contains(where: { lowered.contains($0) }) { return true }
        return TopologyText.words(node.name).contains("t2")
    }

    // MARK: - Nodes

    /// A `DeviceNode` for one USB device, without children.
    static func makeNode(_ device: RawUSBDevice, options: BuildOptions) -> DeviceNode {
        let p = device.node.properties
        let vendorID = p.int("idVendor")
        let productID = p.int("idProduct")
        let locationID = p.int64("locationID").flatMap { UInt32(exactly: $0) }
        let deviceClass = p.int("bDeviceClass")

        let registryName = TopologyText.clean(device.node.name).flatMap { $0 == "IOUSBHostDevice" ? nil : $0 }
        let name = TopologyText.clean(p.string("USB Product Name"))
            ?? TopologyText.clean(p.string("kUSBProductString"))
            ?? registryName
            ?? productID.map { "USB Device \(Format.hex4($0))" }
            ?? "USB Device"

        var usbVersion: String?
        if let bcd = p.int("bcdUSB"), bcd > 0, bcd <= 0xFFFF { usbVersion = Format.bcdVersion(bcd) }

        let isTunneled = p.bool("UsbTunnel") == true || hasTunnelAncestry(device.ancestry)
        let kind = DeviceClassifier.classify(deviceClass: deviceClass, interfaces: device.interfaces, name: name,
                                             vendorID: vendorID)
        return DeviceNode(id: deviceID(locationID: locationID, vendorID: vendorID, productID: productID,
                                       registryID: device.id),
                          registryID: device.id, bus: .usb, kind: kind, name: name,
                          vendorName: TopologyText.clean(p.string("USB Vendor Name"))
                              ?? TopologyText.clean(p.string("kUSBVendorString")),
                          vendorID: vendorID, productID: productID,
                          serialNumber: TopologyText.clean(p.string("USB Serial Number"))
                              ?? TopologyText.clean(p.string("kUSBSerialNumberString")),
                          usbVersion: usbVersion, deviceClass: deviceClass, locationID: locationID,
                          link: LinkDecoding.usbDeviceLink(p), power: power(p), isTunneled: isTunneled,
                          properties: options.includeRawProperties ? p.withoutPlumbing() : nil)
    }

    /// `"usb:<locationID hex 8>:<vid hex 4>:<pid hex 4>"`, with the registry
    /// ID in place of the location when there is none.
    static func deviceID(locationID: UInt32?, vendorID: Int?, productID: Int?, registryID: UInt64) -> String {
        let vid = TopologyText.hex(vendorID ?? 0, width: 4)
        let pid = TopologyText.hex(productID ?? 0, width: 4)
        if let locationID {
            return "usb:\(TopologyText.hex(UInt64(locationID), width: 8)):\(vid):\(pid)"
        }
        return "usb:reg-\(TopologyText.hex(registryID, width: 1)):\(vid):\(pid)"
    }

    /// Allocated power: `UsbPowerSinkAllocation` (mA at 5 V), else the
    /// legacy `Requested Power` (units of 2 mA). Hubs report whether they
    /// bring their own supply (`kUSBHubPowerSupply` > 0 or
    /// `kUSBHubPowerSupplyType` 1).
    static func power(_ p: PropertyBag) -> DevicePower? {
        var milliwatts: Int?
        if let milliamps = p.int("UsbPowerSinkAllocation"), (0...100_000).contains(milliamps) {
            milliwatts = milliamps * 5
        } else if let units = p.int("Requested Power"), (0...50_000).contains(units) {
            milliwatts = units * 2 * 5
        }
        var selfPowered: Bool?
        if let supply = p.int("kUSBHubPowerSupply") { selfPowered = supply > 0 }
        if let type = p.int("kUSBHubPowerSupplyType") {
            if type == 1 { selfPowered = true } else if type == 2, selfPowered == nil { selfPowered = false }
        }
        if milliwatts == nil, selfPowered == nil { return nil }
        return DevicePower(allocatedMilliwatts: milliwatts, source: .usbAllocation, isSelfPowered: selfPowered)
    }

    // MARK: - USB 3 hub companions

    /// Merges each USB 3 hub with its USB 2 companion (same vendor, similar
    /// name, both `bDeviceClass` 9, in the same list) into one node: the
    /// SuperSpeed half keeps its ID and link, and children are combined.
    /// Applied level by level, so nested hub pairs merge too.
    static func mergeCompanionHubs(_ nodes: [DeviceNode]) -> [DeviceNode] {
        let list = nodes.sorted { $0.id < $1.id }
        func isHub(_ n: DeviceNode) -> Bool { n.deviceClass == DeviceClassifier.USBClass.hub }
        func rate(_ n: DeviceNode) -> Int64? { n.link?.bitsPerSecond }

        let fast = list.indices.filter { isHub(list[$0]) && (rate(list[$0]) ?? 0) > LinkDecoding.highSpeed }
        let slow = list.indices.filter { isHub(list[$0]) && (rate(list[$0]).map { $0 <= LinkDecoding.highSpeed } ?? false) }

        var partner: [Int: Int] = [:]
        var used = Set<Int>()
        for f in fast {
            let candidates = slow.filter { s in
                !used.contains(s) && list[s].vendorID != nil && list[s].vendorID == list[f].vendorID
                    && similarHubNames(list[f].name, list[s].name)
            }
            let best = candidates.min { lhs, rhs in
                let l = hubNameKey(list[lhs].name) == hubNameKey(list[f].name) ? 0 : 1
                let r = hubNameKey(list[rhs].name) == hubNameKey(list[f].name) ? 0 : 1
                if l != r { return l < r }
                return (list[lhs].locationID ?? .max, list[lhs].id) < (list[rhs].locationID ?? .max, list[rhs].id)
            }
            if let best {
                partner[f] = best
                used.insert(best)
            }
        }

        var result: [DeviceNode] = []
        for i in list.indices where !used.contains(i) {
            var node = list[i]
            if let s = partner[i] { node = merge(fast: node, slow: list[s]) }
            node.children = mergeCompanionHubs(node.children)
            node.kind = DeviceClassifier.refineHub(node)
            result.append(node)
        }
        return result
    }

    static func merge(fast: DeviceNode, slow: DeviceNode) -> DeviceNode {
        var merged = fast
        merged.children = fast.children + slow.children
        let allocations = [fast.power?.allocatedMilliwatts, slow.power?.allocatedMilliwatts].compactMap { $0 }
        let selfPowered: Bool? = (fast.power?.isSelfPowered == true || slow.power?.isSelfPowered == true)
            ? true : (fast.power?.isSelfPowered ?? slow.power?.isSelfPowered)
        if !allocations.isEmpty || selfPowered != nil {
            // Both halves draw from the same upstream connection: count it once.
            merged.power = DevicePower(allocatedMilliwatts: allocations.max(), source: .usbAllocation,
                                       isSelfPowered: selfPowered)
        }
        merged.isTunneled = fast.isTunneled || slow.isTunneled
        merged.serialNumber = fast.serialNumber ?? slow.serialNumber
        merged.vendorName = fast.vendorName ?? slow.vendorName
        return merged
    }

    /// A hub name without USB version and speed words: "USB3.0 Hub" and
    /// "USB2.0 Hub" both become "hub".
    static func hubNameKey(_ name: String) -> String {
        let noise: Set<String> = ["superspeed", "ss", "hs", "highspeed", "high", "speed", "plus", "x2", "2x2"]
        return TopologyText.words(name).filter { word in
            if word.allSatisfy(\.isNumber) { return false }
            if noise.contains(word) { return false }
            if word.hasPrefix("usb"), word.dropFirst(3).allSatisfy(\.isNumber) { return false }
            if word.hasPrefix("gen"), word.dropFirst(3).allSatisfy(\.isNumber) { return false }
            return true
        }.joined(separator: " ")
    }

    static func similarHubNames(_ a: String, _ b: String) -> Bool {
        let left = hubNameKey(a)
        let right = hubNameKey(b)
        if left == right { return true }
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.contains(right) || right.contains(left)
    }

    // MARK: - Thunderbolt chains

    /// Moves tunnelled USB roots under the Thunderbolt chain device they
    /// belong to, but only when the device's name matches exactly one chain
    /// device (exact first, then containment). Everything else stays at port
    /// level: a wrong parent is worse than a flat list.
    static func nest(_ usbRoots: [DeviceNode], into chains: [DeviceNode]) -> (chains: [DeviceNode], remaining: [DeviceNode]) {
        var chains = chains
        var remaining: [DeviceNode] = []
        for root in usbRoots {
            guard root.isTunneled else { remaining.append(root); continue }
            let chainDevices = chains.flatMap { $0.flattened().map(\.device) }.filter { $0.bus == .thunderbolt }
            let scored = chainDevices.compactMap { device in
                TopologyText.match(root.name, device.name).map { (device.id, $0) }
            }
            let exact = scored.filter { $0.1 == .exact }
            let target = exact.count == 1 ? exact[0].0 : (exact.isEmpty && scored.count == 1 ? scored[0].0 : nil)
            if let target {
                let (updated, inserted) = inserting(root, under: target, in: chains)
                if inserted { chains = updated; continue }
            }
            remaining.append(root)
        }
        return (chains, remaining)
    }

    /// Inserts `child` under the node with ID `target`, searching depth-first.
    static func inserting(_ child: DeviceNode, under target: String, in nodes: [DeviceNode]) -> ([DeviceNode], Bool) {
        var nodes = nodes
        for i in nodes.indices {
            if nodes[i].id == target {
                nodes[i].children.append(child)
                return (nodes, true)
            }
            let (updated, inserted) = inserting(child, under: target, in: nodes[i].children)
            if inserted {
                nodes[i].children = updated
                return (nodes, true)
            }
        }
        return (nodes, false)
    }
}
