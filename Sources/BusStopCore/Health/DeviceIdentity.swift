import Foundation

/// One key per physical device that survives a change of controller, such
/// as a USB 3 drive that falls back to USB 2 and gets a new `locationID`.
/// `DeviceNode.id` embeds the `locationID`, whose top byte is the
/// controller, so it cannot follow the device there.
///
/// Keys stay in memory: they can hold a USB serial number, so they are never
/// written to a file, an event or a diagnostic id.
public enum DeviceIdentity {
    /// `DeviceNode.id` → identity key for every device and built-in dock
    /// part in the snapshot. A key that two devices would share (two hubs
    /// with the same name on one port at one depth, say) is left out, so
    /// two devices are never taken for one.
    ///
    /// - USB with a plausible serial (not empty, not all zeros, unique in the
    ///   snapshot): `"usb:<vid>:<pid>:<serial>"`.
    /// - USB without one: `"usb:<vid>:<pid>@<PortKey>/<route>"`, the route
    ///   being the `locationID` without its controller byte.
    /// - Hubs: `"hub:<vid>:<name>@<PortKey>/<depth>"`, with the name reduced
    ///   by `USBTreeBuilder.hubNameKey`. No product ID and no route: the two
    ///   halves of a USB 3 hub have different product IDs and, at the first
    ///   level, sit on different root ports, so the key holds when the hub
    ///   loses its SuperSpeed half.
    /// - Everything else (Thunderbolt, displays): its `DeviceNode.id`, which
    ///   is already a UID or a display id.
    ///
    /// `sharedSerials` remembers serials seen on two devices at once, so a
    /// device whose twin is unplugged keeps its port-and-route key instead of
    /// switching to the serial and back.
    public static func keys(in snapshot: HostSnapshot, sharedSerials: inout Set<String>) -> [String: String] {
        let entries = Entry.all(in: snapshot)
        var serialCounts: [String: Int] = [:]
        for entry in entries {
            if let serial = serialKey(entry.node) { serialCounts[serial, default: 0] += 1 }
        }
        sharedSerials.formUnion(serialCounts.filter { $0.value > 1 }.keys)
        var owners: [String: Set<String>] = [:]
        var result: [String: String] = [:]
        for entry in entries {
            guard let key = key(for: entry, sharedSerials: sharedSerials) else { continue }
            result[entry.node.id] = key
            owners[key, default: []].insert(entry.node.id)
        }
        return result.filter { owners[$0.value]?.count == 1 }
    }

    /// `keys(in:sharedSerials:)` for one snapshot on its own.
    public static func keys(in snapshot: HostSnapshot) -> [String: String] {
        var shared = Set<String>()
        return keys(in: snapshot, sharedSerials: &shared)
    }

    private static func key(for entry: Entry, sharedSerials: Set<String>) -> String? {
        let node = entry.node
        guard node.bus == .usb else { return node.id }
        let vid = TopologyText.hex(node.vendorID ?? 0, width: 4)
        let port = entry.port?.key.description ?? "-"
        if DiagnosticsEngine.isHub(node) {
            return "hub:\(vid):\(USBTreeBuilder.hubNameKey(node.name))@\(port)/\(entry.depth)"
        }
        if let serial = serialKey(node), !sharedSerials.contains(serial) { return serial }
        guard let location = node.locationID else { return nil }
        let pid = TopologyText.hex(node.productID ?? 0, width: 4)
        return "usb:\(vid):\(pid)@\(port)/\(TopologyText.hex(UInt64(location & 0x00FF_FFFF), width: 6))"
    }

    /// `"usb:<vid>:<pid>:<serial>"` when the serial looks like a real one.
    private static func serialKey(_ node: DeviceNode) -> String? {
        guard node.bus == .usb, !DiagnosticsEngine.isHub(node),
              let serial = node.serialNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
              !serial.isEmpty, !serial.allSatisfy({ $0 == "0" }) else { return nil }
        let vid = TopologyText.hex(node.vendorID ?? 0, width: 4)
        let pid = TopologyText.hex(node.productID ?? 0, width: 4)
        return "usb:\(vid):\(pid):\(serial)"
    }

    /// A device or built-in part with where it sits.
    struct Entry {
        var node: DeviceNode
        var port: PhysicalPort?
        /// The `DeviceNode.id` it hangs off: the built-in part for a device
        /// a dock folded up, the dock for a part at its top. Nil at a port.
        var parentID: String?
        /// 0 for a device plugged straight into the port.
        var depth: Int
        /// The dock a built-in part belongs to; nil for other devices.
        var dock: DeviceNode?

        /// Every device in every tree, then every dock's built-in parts.
        static func all(in snapshot: HostSnapshot) -> [Entry] {
            var result: [Entry] = []
            // A stack, not recursion: trees can be 64 levels deep.
            var stack: [Entry] = snapshot.otherDevices.reversed().map { Entry(node: $0, depth: 0) }
            for port in snapshot.ports.reversed() {
                stack += port.devices.reversed().map { Entry(node: $0, port: port, depth: 0) }
            }
            while let entry = stack.popLast() {
                result.append(entry)
                stack += entry.node.children.reversed().map { child in
                    Entry(node: child, port: entry.port, parentID: child.internalParentID ?? entry.node.id,
                          depth: entry.depth + 1)
                }
            }
            for entry in result {
                for part in entry.node.internalParts ?? [] {
                    result.append(Entry(node: part, port: entry.port,
                                        parentID: part.internalParentID ?? entry.node.id,
                                        depth: entry.depth + 1, dock: entry.node))
                }
            }
            return result
        }

        init(node: DeviceNode, port: PhysicalPort? = nil, parentID: String? = nil, depth: Int,
             dock: DeviceNode? = nil) {
            self.node = node
            self.port = port
            self.parentID = parentID
            self.depth = depth
            self.dock = dock
        }
    }
}
