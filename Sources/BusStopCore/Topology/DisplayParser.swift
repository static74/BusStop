import Foundation

/// Displays and the ports they are attached to (SPEC §5.4 "Displays").
enum DisplayParser {
    /// `"display:<vendor hex>:<product hex>:<serial>"`, with `cg<ID>` in place
    /// of a missing or zero serial number.
    static func displayID(_ display: RawDisplay) -> String {
        let vendor = TopologyText.hex(display.vendorID ?? 0, width: 1)
        let product = TopologyText.hex(display.productID ?? 0, width: 1)
        let serial = display.serialNumber.flatMap { $0 != 0 ? String($0) : nil } ?? "cg\(display.id)"
        return "display:\(vendor):\(product):\(serial)"
    }

    static func info(_ display: RawDisplay) -> DisplayInfo {
        let name = TopologyText.clean(display.name) ?? (display.isBuiltin ? "Built-in Display" : "External Display")
        let refresh = display.refreshHz.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return DisplayInfo(id: displayID(display), name: name, vendorID: display.vendorID, productID: display.productID,
                           serialNumber: display.serialNumber, isBuiltin: display.isBuiltin,
                           pixelWidth: display.pixelWidth.flatMap { $0 > 0 ? $0 : nil },
                           pixelHeight: display.pixelHeight.flatMap { $0 > 0 ? $0 : nil }, refreshHz: refresh)
    }

    /// A display tied to a port, and how it should appear in the port's tree.
    struct Attribution {
        var portKey: PortKey
        var link: LinkInfo?
        var isTunneled: Bool
        /// A Thunderbolt chain device already stands for this display.
        var representedByThunderbolt: Bool
    }

    /// Ties external displays to ports, most reliable evidence first:
    /// 1. an active DisplayPort transport whose `ProductName` matches;
    /// 2. a Thunderbolt chain device of kind display with a matching name;
    /// 3. when exactly one port still carries video (DisplayPort, CIO or a
    ///    connected HDMI port) and exactly one external display is left.
    ///
    /// - Parameters:
    ///   - displays: built display records, sorted.
    ///   - dpTransports: active DisplayPort transports (tunnelled or not), sorted.
    ///   - chainsByPort: Thunderbolt chains per port.
    ///   - videoPorts: ports that carry DisplayPort, CIO or HDMI, sorted.
    static func attribute(_ displays: [DisplayInfo], dpTransports: [TopologyTransportRecord],
                          chainsByPort: [PortKey: [DeviceNode]], videoPorts: [PortKey]) -> [String: Attribution] {
        var result: [String: Attribution] = [:]
        var usedTransports = Set<UInt64>()
        var usedChainDevices = Set<String>()
        let externals = displays.filter { !$0.isBuiltin }

        for display in externals {
            let matches = dpTransports.filter { !usedTransports.contains($0.node.id) }
                .compactMap { record in TopologyText.match(display.name, record.productName).map { (record, $0) } }
            guard let best = matches.max(by: { $0.1 < $1.1 }) else { continue }
            usedTransports.insert(best.0.node.id)
            result[display.id] = Attribution(portKey: best.0.portKey, link: best.0.link,
                                             isTunneled: best.0.isTunneled, representedByThunderbolt: false)
        }

        var chainDisplays: [(key: PortKey, device: DeviceNode)] = []
        for key in chainsByPort.keys.sorted() {
            for chain in chainsByPort[key] ?? [] {
                for entry in chain.flattened() where entry.device.bus == .thunderbolt && entry.device.kind == .display {
                    chainDisplays.append((key, entry.device))
                }
            }
        }
        for display in externals {
            var best: (key: PortKey, device: DeviceNode, strength: TopologyText.NameMatch)?
            for entry in chainDisplays where !usedChainDevices.contains(entry.device.id) {
                guard let strength = TopologyText.match(display.name, entry.device.name) else { continue }
                if let current = best, strength <= current.strength { continue }
                best = (entry.key, entry.device, strength)
            }
            guard let key = best?.key, let device = best?.device else { continue }
            usedChainDevices.insert(device.id)
            if var existing = result[display.id] {
                existing.representedByThunderbolt = existing.portKey == key
                result[display.id] = existing
            } else {
                result[display.id] = Attribution(portKey: key, link: device.link, isTunneled: true,
                                                 representedByThunderbolt: true)
            }
        }

        let taken = Set(result.values.map(\.portKey))
        let freePorts = videoPorts.filter { !taken.contains($0) }
        let left = externals.filter { result[$0.id] == nil }
        if freePorts.count == 1, left.count == 1 {
            let key = freePorts[0]
            let transport = dpTransports.first { $0.portKey == key && !$0.isTunneled }
                ?? dpTransports.first { $0.portKey == key }
            result[left[0].id] = Attribution(portKey: key, link: transport?.link,
                                             isTunneled: transport?.isTunneled ?? false, representedByThunderbolt: false)
        }
        return result
    }

    /// The device row for a display attributed to a port.
    static func deviceNode(_ display: DisplayInfo, attribution: Attribution) -> DeviceNode {
        DeviceNode(id: display.id, bus: .displayPort, kind: .display, name: display.name,
                   vendorID: display.vendorID, productID: display.productID,
                   serialNumber: display.serialNumber.flatMap { $0 != 0 ? String($0) : nil },
                   link: attribution.link, isTunneled: attribution.isTunneled)
    }
}
