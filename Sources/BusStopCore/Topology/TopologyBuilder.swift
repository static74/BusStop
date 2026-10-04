import Foundation

/// Options that change how a `RawSnapshot` is interpreted.
public struct BuildOptions: Sendable, Hashable {
    /// Port key (`"2/1"`) → user-chosen port name.
    public var userPortNames: [String: String]
    /// Copy raw IORegistry properties onto ports and devices for the inspector.
    public var includeRawProperties: Bool
    /// Mark the result as demo data.
    public var isDemo: Bool

    public init(userPortNames: [String: String] = [:], includeRawProperties: Bool = true, isDemo: Bool = false) {
        self.userPortNames = userPortNames
        self.includeRawProperties = includeRawProperties
        self.isDemo = isDemo
    }
}

/// Turns raw IORegistry data into the port → device topology.
///
/// Pure and deterministic: the same `RawSnapshot` and options always produce
/// the same `HostSnapshot`. See `docs/SPEC.md` §5.4 for the rules. The work
/// is split by subject: `PortParser`, `TransportParser`, `ThunderboltParser`,
/// `USBTreeBuilder`, `DeviceClassifier`, `DisplayParser`, `PowerParser` and
/// `LinkDecoding`.
public enum TopologyBuilder {
    /// Capture note added when no port controller was found (Intel Macs,
    /// virtual machines). `DiagnosticsEngine` reports it as reduced detail.
    public static let noPortDetailNote = "Port controller details are not available on this Mac."

    public static func build(_ raw: RawSnapshot, options: BuildOptions = BuildOptions()) -> HostSnapshot {
        let index = TopologyNodeIndex(raw.portNodes)
        let ports = PortParser.parse(index)
        let transports = TransportParser.parse(index, ports: ports)
        let thunderbolt = ThunderboltParser.parse(raw.thunderboltSwitches, options: options)

        // Transports per port, and which ports have CIO up.
        var activeTransports: [PortKey: [TransportInfo]] = [:]
        for record in ports.records {
            activeTransports[record.key] = TransportParser.activeTransports(for: record, transports: transports)
        }
        let cioActivePorts = ports.keys.filter { key in
            activeTransports[key]?.contains { $0.kind == .cio } == true
        }

        // Thunderbolt link and chains per port (Socket ID = USB-C number).
        var thunderboltLinks: [PortKey: LinkInfo] = [:]
        var chains: [PortKey: [DeviceNode]] = [:]
        var otherDevices = thunderbolt.unattributedChains
        for socket in thunderbolt.allSockets.union(thunderbolt.chains.keys).sorted() {
            let key = ports.usbCKey(number: socket)
            if let key {
                let link = thunderbolt.liveLinks[socket]
                    ?? (cioActivePorts.contains(key) ? thunderbolt.decodedLinks[socket] : nil)
                if let link { thunderboltLinks[key] = link }
            }
            guard let socketChains = thunderbolt.chains[socket], !socketChains.isEmpty else { continue }
            if let key {
                chains[key, default: []].append(contentsOf: socketChains)
            } else {
                otherDevices.append(contentsOf: socketChains)
            }
        }
        for record in ports.records {
            activeTransports[record.key] = withThunderbolt(activeTransports[record.key] ?? [],
                                                           link: thunderboltLinks[record.key], record: record)
        }

        // USB trees, attributed to ports.
        var transportPorts: [UInt64: PortKey] = [:]
        for transport in transports { transportPorts[transport.node.id] = transport.portKey }
        let context = USBAttributionContext(ports: ports, index: index, transportPorts: transportPorts,
                                            thunderbolt: thunderbolt, cioActivePorts: cioActivePorts)
        let usb = USBTreeBuilder.build(raw.usbDevices, context: context, options: options)
        otherDevices.append(contentsOf: usb.unattributed)

        var devices: [PortKey: [DeviceNode]] = [:]
        for record in ports.records {
            let (nested, remaining) = USBTreeBuilder.nest(usb.byPort[record.key] ?? [], into: chains[record.key] ?? [])
            devices[record.key] = nested + remaining
        }

        // Displays.
        let displays = raw.displays.map(DisplayParser.info).sorted(by: displayOrder)
        let dpTransports = transports.filter { record in
            guard record.kind == .displayPort else { return false }
            if record.activeFlag == true { return true }
            return record.activeFlag == nil && !record.isTunneled
                && ports.record(record.portKey)?.listedActiveTransports?.contains(.displayPort) == true
        }
        let videoPorts = ports.records.filter { record in
            let kinds = Set((activeTransports[record.key] ?? []).map(\.kind))
            return kinds.contains(.displayPort) || kinds.contains(.cio) || kinds.contains(.hdmi)
                || (record.kind == .hdmi && record.connectionActive)
                || dpTransports.contains { $0.portKey == record.key }
        }.map(\.key)
        let attributions = DisplayParser.attribute(displays, dpTransports: dpTransports, chainsByPort: chains,
                                                   videoPorts: videoPorts)
        var displayInfos: [DisplayInfo] = []
        for var display in displays {
            if let attribution = attributions[display.id] {
                display.portKey = attribution.portKey
                display.link = attribution.link
                if !attribution.representedByThunderbolt {
                    devices[attribution.portKey, default: []].append(DisplayParser.deviceNode(display, attribution: attribution))
                }
            }
            displayInfos.append(display)
        }

        // Ports without power yet.
        var physicalPorts: [PhysicalPort] = []
        for record in ports.records {
            let active = activeTransports[record.key] ?? []
            let portDevices = devices[record.key] ?? []
            var link: LinkInfo?
            for transport in active { link = LinkDecoding.faster(link, transport.link) }
            let isConnected = record.connectionActive || !active.isEmpty || !portDevices.isEmpty
                || thunderboltLinks[record.key] != nil
            let supported = record.supportedTransports ?? []
            let hasSocket = (record.kind == .usbC || record.kind == .thunderbolt)
                && thunderbolt.allSockets.contains(record.number)
            let supportsThunderbolt: Bool? = (supported.contains(.cio) || hasSocket)
                ? true : (record.supportedTransports == nil ? nil : false)
            let siblings = ports.records.filter { $0.kind == record.kind }.map(\.number).sorted()
            let labelled = PortLabeler.label(kind: record.kind, number: record.number, key: record.key,
                                             siblings: siblings, model: raw.machine.model,
                                             userNames: options.userPortNames,
                                             supportsThunderbolt: supportsThunderbolt)
            physicalPorts.append(PhysicalPort(
                key: record.key, kind: record.kind, number: record.number, registryName: record.registryName,
                label: labelled.label, capabilityDescription: labelled.capability, supportedTransports: supported,
                activeTransports: active, isConnected: isConnected, link: link,
                cable: TransportParser.cable(for: record, index: index, ports: ports),
                devices: sortedTree(portDevices), statistics: PortParser.statistics(record),
                liquidDetected: TransportParser.liquidDetected(for: record, index: index, ports: ports),
                properties: options.includeRawProperties ? record.properties.withoutPlumbing() : nil))
        }

        // Power.
        let telemetry = PowerParser.telemetry(raw.battery)
        let connected = Set(physicalPorts.filter(\.isConnected).map(\.key))
        let chargerPort = PowerParser.chargerPort(ports: ports, index: index, connected: connected)
        var charger = PowerParser.charger(raw, portEvidence: chargerPort != nil)
        if var found = charger, let chargerPort {
            found.portKey = chargerPort.key
            PowerParser.enrich(&found, port: chargerPort.key, ports: ports, index: index)
            charger = found
        }
        let smc = PowerParser.smcChannels(raw, ports: ports)
        let powerOut = PowerParser.powerOutDetails(raw.battery)
        for i in physicalPorts.indices {
            let key = physicalPorts[i].key
            let isChargerPort = charger != nil && charger?.portKey == key
            if isChargerPort { physicalPorts[i].charger = charger }
            physicalPorts[i].power = PowerParser.portPower(for: physicalPorts[i], isChargerPort: isChargerPort,
                                                            charger: charger, smc: smc[key], powerOut: powerOut,
                                                            telemetry: telemetry)
        }
        let hasBattery = PowerParser.hasBattery(raw)
        let power = PowerSummary(
            charger: charger, battery: PowerParser.battery(raw, telemetry: telemetry),
            systemInputMilliwatts: telemetry.systemInput, systemLoadMilliwatts: telemetry.systemLoad,
            portOutputMilliwatts: physicalPorts.reduce(0) { total, port in
                port.power?.direction == .output ? total + (port.power?.milliwatts ?? 0) : total
            },
            usbAllocatedMilliwatts: physicalPorts.reduce(0) { $0 + $1.allocatedMilliwatts },
            hasBattery: hasBattery)

        // Physical order.
        var order: [PortKey: (Int, Int, Int)] = [:]
        for port in physicalPorts {
            let siblings = physicalPorts.filter { $0.kind == port.kind }.map(\.number).sorted()
            order[port.key] = PortLabeler.sortKey(kind: port.kind, number: port.number, siblings: siblings,
                                                  model: raw.machine.model)
        }
        physicalPorts.sort { lhs, rhs in
            let l = order[lhs.key] ?? (Int.max, Int.max, Int.max)
            let r = order[rhs.key] ?? (Int.max, Int.max, Int.max)
            if l != r { return l < r }
            return lhs.key < rhs.key
        }

        var notes = raw.captureNotes
        if physicalPorts.isEmpty, !notes.contains(noPortDetailNote) { notes.append(noPortDetailNote) }

        var snapshot = HostSnapshot(
            capturedAt: raw.capturedAt,
            machine: MachineSummary(model: raw.machine.model, name: machineName(raw.machine.model),
                                    chip: raw.machine.chip, osVersion: raw.machine.osVersion, isLaptop: hasBattery,
                                    isAppleSilicon: raw.machine.isAppleSilicon),
            ports: physicalPorts, otherDevices: sortedTree(otherDevices), displays: displayInfos, power: power,
            captureNotes: notes, isDemo: options.isDemo)
        makeDeviceIDsUnique(&snapshot)
        snapshot.diagnostics = DiagnosticsEngine.evaluate(snapshot, raw: raw)
        return snapshot
    }

    // MARK: - Helpers

    /// Puts the Thunderbolt link on the port's CIO transport. When the port
    /// does not publish `TransportsActive`, a live Thunderbolt link also adds
    /// a CIO entry; otherwise that list stays authoritative.
    static func withThunderbolt(_ transports: [TransportInfo], link: LinkInfo?,
                                record: TopologyPortRecord) -> [TransportInfo] {
        var result = transports
        if let i = result.firstIndex(where: { $0.kind == .cio }) {
            result[i].link = link ?? result[i].link
        } else if let link, record.listedActiveTransports == nil {
            result.append(TransportInfo(kind: .cio, isActive: true, link: link))
            result.sort { $0.kind < $1.kind }
        }
        return result
    }

    /// Marketing name from the catalogue, else a readable name from the
    /// model identifier prefix.
    static func machineName(_ model: String) -> String {
        if let name = PortLocationCatalog.marketingName(for: model) { return name }
        return heuristicMachineName(model)
    }

    static func heuristicMachineName(_ model: String) -> String {
        let prefixes: [(String, String)] = [
            ("MacBookPro", "MacBook Pro"), ("MacBookAir", "MacBook Air"), ("MacBook", "MacBook"),
            ("Macmini", "Mac mini"), ("iMacPro", "iMac Pro"), ("iMac", "iMac"), ("MacPro", "Mac Pro"),
        ]
        for (prefix, name) in prefixes where model.hasPrefix(prefix) {
            let rest = model.dropFirst(prefix.count)
            if rest.isEmpty || rest.first?.isNumber == true { return name }
        }
        return model.isEmpty ? "Mac" : "Mac (\(model))"
    }

    /// Built-in display first, then by name and ID.
    static func displayOrder(_ lhs: DisplayInfo, _ rhs: DisplayInfo) -> Bool {
        if lhs.isBuiltin != rhs.isBuiltin { return lhs.isBuiltin }
        return deviceNameOrder(lhs.name, lhs.id, rhs.name, rhs.id)
    }

    /// Case-insensitive name, then exact name, then ID.
    static func deviceNameOrder(_ lName: String, _ lID: String, _ rName: String, _ rID: String) -> Bool {
        let l = lName.lowercased()
        let r = rName.lowercased()
        if l != r { return l < r }
        if lName != rName { return lName < rName }
        return lID < rID
    }

    /// Sorts devices by name then ID at every level.
    static func sortedTree(_ nodes: [DeviceNode]) -> [DeviceNode] {
        nodes.map { node in
            var copy = node
            copy.children = sortedTree(node.children)
            return copy
        }.sorted { deviceNameOrder($0.name, $0.id, $1.name, $1.id) }
    }

    /// Device IDs must be unique for lists and selection. A repeat (only
    /// possible with odd captures) gets its registry ID appended.
    static func makeDeviceIDsUnique(_ snapshot: inout HostSnapshot) {
        var seen = Set<String>()
        func fix(_ nodes: inout [DeviceNode]) {
            for i in nodes.indices {
                if !seen.insert(nodes[i].id).inserted {
                    let base = nodes[i].id + "#" + (nodes[i].registryID.map { TopologyText.hex($0, width: 1) } ?? "dup")
                    var candidate = base
                    var n = 2
                    while !seen.insert(candidate).inserted {
                        candidate = "\(base)-\(n)"
                        n += 1
                    }
                    nodes[i].id = candidate
                }
                fix(&nodes[i].children)
            }
        }
        for i in snapshot.ports.indices { fix(&snapshot.ports[i].devices) }
        fix(&snapshot.otherDevices)
    }
}
