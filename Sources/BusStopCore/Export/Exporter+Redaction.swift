import Foundation

/// Redaction for exports.
///
/// What is removed:
/// - every `serialNumber` of devices, chargers and displays (display serials
///   are numbers, so they become nil; the others become "REDACTED");
/// - in every property bag, at any depth, values whose key contains "serial"
///   (any case) or is "ConnectionUUID";
/// - the serial number fields inside EDID blobs;
/// - the computer name of a raw capture;
/// - serial numbers that appear as parts of device, display and diagnostic ids
///   (display ids can end in the panel's serial number).
extension Exporter {
    /// A copy of the snapshot with identifying values removed.
    public static func redacted(_ snapshot: HostSnapshot) -> HostSnapshot {
        let scrubber = IDScrubber(serials: serialStrings(in: snapshot))
        var copy = snapshot
        copy.ports = snapshot.ports.map { port in
            var port = port
            port.devices = port.devices.map { redacted($0, scrubber: scrubber) }
            port.charger = port.charger.map(redacted(_:))
            port.properties = port.properties.map(redacted(_:))
            return port
        }
        copy.otherDevices = snapshot.otherDevices.map { redacted($0, scrubber: scrubber) }
        copy.power.charger = snapshot.power.charger.map(redacted(_:))
        copy.displays = snapshot.displays.map { display in
            var display = display
            display.serialNumber = nil
            display.id = scrubber.scrub(display.id)
            return display
        }
        copy.diagnostics = snapshot.diagnostics.map { diagnostic in
            var diagnostic = diagnostic
            diagnostic.id = scrubber.scrub(diagnostic.id)
            diagnostic.deviceID = diagnostic.deviceID.map(scrubber.scrub)
            return diagnostic
        }
        return copy
    }

    /// A copy of the raw capture with serials redacted in every property bag,
    /// display serials removed and no computer name.
    public static func redacted(_ raw: RawSnapshot) -> RawSnapshot {
        var copy = raw
        copy.machine.computerName = nil
        copy.portNodes = raw.portNodes.map(redacted(_:))
        copy.usbDevices = raw.usbDevices.map { device in
            var device = device
            device.node = redacted(device.node)
            return device
        }
        copy.thunderboltSwitches = raw.thunderboltSwitches.map { sw in
            var sw = sw
            sw.node = redacted(sw.node)
            sw.ports = sw.ports.map(redacted(_:))
            return sw
        }
        copy.battery = raw.battery.map(redacted(_:))
        copy.adapter = raw.adapter.map(redacted(_:))
        copy.displays = raw.displays.map { display in
            var display = display
            display.serialNumber = nil
            return display
        }
        return copy
    }

    /// A copy of the bag with sensitive values replaced, at every depth.
    public static func redacted(_ bag: PropertyBag) -> PropertyBag {
        PropertyBag(redacted(bag.values))
    }

    /// True for property keys whose values identify a specific unit:
    /// any key containing "serial" (any case) and "ConnectionUUID".
    public static func isSensitiveKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        return lower.contains("serial") || lower == "connectionuuid"
    }

    // MARK: Private

    private static func redacted(_ node: RawNode) -> RawNode {
        var node = node
        node.properties = redacted(node.properties)
        return node
    }

    private static func redacted(_ device: DeviceNode, scrubber: IDScrubber) -> DeviceNode {
        var device = device
        device.id = scrubber.scrub(device.id)
        if device.serialNumber != nil { device.serialNumber = redactedText }
        device.properties = device.properties.map(redacted(_:))
        device.children = device.children.map { redacted($0, scrubber: scrubber) }
        return device
    }

    private static func redacted(_ charger: ChargerInfo) -> ChargerInfo {
        var charger = charger
        if charger.serialNumber != nil { charger.serialNumber = redactedText }
        return charger
    }

    private static func redacted(_ values: [String: PlistValue]) -> [String: PlistValue] {
        var result: [String: PlistValue] = [:]
        for (key, value) in values {
            if isSensitiveKey(key) {
                result[key] = .string(redactedText)
            } else if key.lowercased() == "edid", case .data(let data) = value {
                result[key] = .data(redactedEDID(data))
            } else {
                result[key] = redacted(value)
            }
        }
        return result
    }

    private static func redacted(_ value: PlistValue) -> PlistValue {
        switch value {
        case .dict(let values): return .dict(redacted(values))
        case .array(let items): return .array(items.map(redacted(_:)))
        default: return value
        }
    }

    /// An EDID with its serial fields blanked: bytes 12–15 (the numeric
    /// serial) and the text of any "display serial number" descriptor (tag
    /// 0xFF). The base-block checksum is recomputed so the blob stays valid.
    /// Blobs shorter than one 128-byte block are returned unchanged.
    static func redactedEDID(_ data: Data) -> Data {
        guard data.count >= 128 else { return data }
        var bytes = [UInt8](data)
        for index in 12...15 { bytes[index] = 0 }
        for offset in stride(from: 54, through: 108, by: 18)
        where bytes[offset] == 0 && bytes[offset + 1] == 0 && bytes[offset + 3] == 0xFF {
            for index in (offset + 5)..<(offset + 18) { bytes[index] = 0x20 }
        }
        let sum = bytes[0..<127].reduce(0) { ($0 + Int($1)) & 0xFF }
        bytes[127] = UInt8((256 - sum) & 0xFF)
        return Data(bytes)
    }

    /// Serial numbers in the snapshot, as they could appear inside ids.
    private static func serialStrings(in snapshot: HostSnapshot) -> Set<String> {
        var serials = Set<String>()
        for display in snapshot.displays {
            if let serial = display.serialNumber, serial != 0 {
                serials.insert(String(serial))
                serials.insert(String(serial, radix: 16))
            }
        }
        for entry in snapshot.allDevices {
            if let serial = entry.device.serialNumber { serials.insert(serial) }
        }
        return serials
    }
}

/// Replaces serial numbers that form a whole `:`-separated part of an id.
///
/// Parts shorter than three characters are left alone: displays without a
/// serial report 0 or 1, and such short values identify nothing.
private struct IDScrubber {
    var serials: Set<String>

    init(serials: Set<String>) {
        self.serials = Set(serials.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count >= 3 })
    }

    func scrub(_ id: String) -> String {
        guard !serials.isEmpty else { return id }
        let parts = id.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let scrubbed = parts.map { serials.contains($0) ? Exporter.redactedText : $0 }
        return scrubbed.joined(separator: ":")
    }
}
