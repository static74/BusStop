import Foundation

/// Compares two snapshots and describes what changed.
///
/// Devices are matched by `DeviceNode.id` across every port and the "other
/// devices" list, so a device that moves between ports is neither connected
/// nor disconnected. When a hub or dock comes or goes with devices behind it,
/// one event describes the whole subtree ("USB hub disconnected", detail
/// "… · and 3 more devices").
public enum SnapshotDiffer {
    /// Events in a stable order: disconnections, connections, link changes,
    /// charger and display changes, new diagnostics.
    /// Returns no events when `old` is nil (first capture).
    ///
    /// Event ids are `"<kind>:<subject>:<milliseconds since 1970>"`, where the
    /// subject is a device id, a display id, a diagnostic id or `"charger"`.
    public static func events(from old: HostSnapshot?, to new: HostSnapshot, at date: Date) -> [ConnectionEvent] {
        guard let old else { return [] }
        let stamp = milliseconds(date)
        let before = DeviceIndex(old)
        let after = DeviceIndex(new)

        func makeID(_ kind: ConnectionEvent.Kind, _ subject: String) -> String {
            "\(kind.rawValue):\(subject):\(stamp)"
        }

        var events: [ConnectionEvent] = []

        // Disconnections, then connections: only the top-most changed device of
        // each subtree, with the rest counted in the detail.
        for (kind, from, to) in [(ConnectionEvent.Kind.deviceDisconnected, before, after),
                                 (ConnectionEvent.Kind.deviceConnected, after, before)] {
            for entry in from.entries where to.byID[entry.device.id] == nil {
                if let parentID = entry.parentID, to.byID[parentID] == nil { continue }
                let hidden = entry.device.flattened().dropFirst().filter { to.byID[$0.device.id] == nil }.count
                var parts = deviceContext(entry.device, port: entry.port)
                if hidden > 0 { parts.append(hidden == 1 ? "and 1 more device" : "and \(hidden) more devices") }
                let verb = kind == .deviceConnected ? "connected" : "disconnected"
                events.append(ConnectionEvent(
                    id: makeID(kind, entry.device.id),
                    date: date,
                    kind: kind,
                    title: "\(name(of: entry.device)) \(verb)",
                    detail: parts.joined(separator: " · "),
                    portKey: entry.port?.key,
                    deviceID: entry.device.id))
            }
        }

        // Link speed changes on devices present in both snapshots.
        for entry in after.entries {
            guard let previous = before.byID[entry.device.id],
                  let oldRate = previous.device.link?.bitsPerSecond, let newRate = entry.device.link?.bitsPerSecond,
                  oldRate != newRate else { continue }
            let slower = newRate < oldRate
            var parts: [String] = []
            if let port = entry.port { parts.append(port.label.title) }
            parts.append("\(linkText(previous.device.link)) → \(linkText(entry.device.link))")
            events.append(ConnectionEvent(
                id: makeID(.linkChanged, entry.device.id),
                date: date,
                kind: .linkChanged,
                title: "\(name(of: entry.device)) \(slower ? "slowed down" : "sped up")",
                detail: parts.joined(separator: " · "),
                portKey: entry.port?.key,
                deviceID: entry.device.id,
                isDowngrade: slower))
        }

        events += chargerEvents(old: old, new: new, date: date, makeID: makeID)
        events += displayEvents(old: old, new: new, date: date, makeID: makeID)

        // Diagnostics that were not raised before.
        let oldDiagnostics = Set(old.diagnostics.map(\.id))
        var raised = Set<String>()
        for diagnostic in new.diagnostics
        where !oldDiagnostics.contains(diagnostic.id) && raised.insert(diagnostic.id).inserted {
            events.append(ConnectionEvent(
                id: makeID(.diagnosticRaised, diagnostic.id),
                date: date,
                kind: .diagnosticRaised,
                title: diagnostic.title,
                detail: diagnostic.detail,
                portKey: diagnostic.portKey,
                deviceID: diagnostic.deviceID))
        }
        return events
    }

    // MARK: Charger

    private static func chargerEvents(old: HostSnapshot, new: HostSnapshot, date: Date,
                                      makeID: (ConnectionEvent.Kind, String) -> String) -> [ConnectionEvent] {
        switch (old.power.charger, new.power.charger) {
        case (nil, let charger?):
            return [ConnectionEvent(id: makeID(.chargerConnected, "charger"), date: date, kind: .chargerConnected,
                                    title: "\(charger.displayName) connected",
                                    detail: chargerContext(charger, in: new).joined(separator: " · "),
                                    portKey: charger.portKey)]
        case (let charger?, nil):
            return [ConnectionEvent(id: makeID(.chargerDisconnected, "charger"), date: date, kind: .chargerDisconnected,
                                    title: "\(charger.displayName) disconnected",
                                    detail: chargerContext(charger, in: old).joined(separator: " · "),
                                    portKey: charger.portKey)]
        case (let before?, let after?) where before.displayName != after.displayName:
            // A different adapter (or the same one, now identified by name).
            var parts = chargerContext(after, in: new)
            parts.append("replaces \(before.displayName)")
            return [ConnectionEvent(id: makeID(.chargerConnected, "charger"), date: date, kind: .chargerConnected,
                                    title: "\(after.displayName) connected",
                                    detail: parts.joined(separator: " · "),
                                    portKey: after.portKey)]
        default:
            return []
        }
    }

    /// Port, contract and rating of a charger: "Left Rear · MagSafe · 20 V × 4.7 A · 96 W".
    private static func chargerContext(_ charger: ChargerInfo, in snapshot: HostSnapshot) -> [String] {
        var parts: [String] = []
        if let key = charger.portKey, let port = snapshot.port(key) { parts.append(port.label.title) }
        if let mv = charger.millivolts, let ma = charger.milliamps, mv > 0, ma > 0 {
            parts.append(Format.contract(millivolts: mv, milliamps: ma))
        }
        if let watts = charger.ratedWatts, watts > 0 { parts.append("\(watts) W") }
        return parts
    }

    // MARK: Displays

    /// External displays that appeared or went away. Built-in panels are left
    /// out: closing the lid would otherwise read as a disconnection.
    private static func displayEvents(old: HostSnapshot, new: HostSnapshot, date: Date,
                                      makeID: (ConnectionEvent.Kind, String) -> String) -> [ConnectionEvent] {
        let oldIDs = Set(old.displays.map(\.id))
        let newIDs = Set(new.displays.map(\.id))
        var events: [ConnectionEvent] = []
        var seen = Set<String>()
        for display in old.displays where !display.isBuiltin && !newIDs.contains(display.id)
            && seen.insert(display.id).inserted {
            events.append(ConnectionEvent(id: makeID(.displayDisconnected, display.id), date: date,
                                          kind: .displayDisconnected, title: "\(displayName(display)) disconnected",
                                          detail: displayContext(display, in: old).joined(separator: " · "),
                                          portKey: display.portKey))
        }
        seen.removeAll()
        for display in new.displays where !display.isBuiltin && !oldIDs.contains(display.id)
            && seen.insert(display.id).inserted {
            events.append(ConnectionEvent(id: makeID(.displayConnected, display.id), date: date,
                                          kind: .displayConnected, title: "\(displayName(display)) connected",
                                          detail: displayContext(display, in: new).joined(separator: " · "),
                                          portKey: display.portKey))
        }
        return events
    }

    private static func displayContext(_ display: DisplayInfo, in snapshot: HostSnapshot) -> [String] {
        var parts: [String] = []
        if let key = display.portKey, let port = snapshot.port(key) { parts.append(port.label.title) }
        if let link = display.link { parts.append(link.label) }
        if let mode = display.modeDescription { parts.append(mode) }
        return parts
    }

    private static func displayName(_ display: DisplayInfo) -> String {
        let name = display.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Display" : name
    }

    // MARK: Devices

    /// Every device in a snapshot with its port and parent, in display order.
    private struct DeviceIndex {
        struct Entry {
            var device: DeviceNode
            var port: PhysicalPort?
            var parentID: String?
        }

        var entries: [Entry] = []
        var byID: [String: Entry] = [:]

        init(_ snapshot: HostSnapshot) {
            for port in snapshot.ports {
                for root in port.devices { add(root, port: port, parentID: nil) }
            }
            for root in snapshot.otherDevices { add(root, port: nil, parentID: nil) }
        }

        private mutating func add(_ device: DeviceNode, port: PhysicalPort?, parentID: String?) {
            // A repeated id keeps its first position so lookups stay stable.
            if byID[device.id] == nil {
                let entry = Entry(device: device, port: port, parentID: parentID)
                entries.append(entry)
                byID[device.id] = entry
            }
            for child in device.children { add(child, port: port, parentID: device.id) }
        }
    }

    /// Port title, then link: "Left Front · USB-C · USB 3.2 Gen 2 @ 10 Gb/s".
    private static func deviceContext(_ device: DeviceNode, port: PhysicalPort?) -> [String] {
        var parts: [String] = []
        if let port { parts.append(port.label.title) }
        if let link = device.link { parts.append(link.label) }
        if parts.isEmpty { parts.append(device.kind.displayName) }
        return parts
    }

    private static func linkText(_ link: LinkInfo?) -> String {
        link?.label ?? "unknown speed"
    }

    private static func name(of device: DeviceNode) -> String {
        let name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? device.kind.displayName : name
    }

    /// Milliseconds since 1970, rounded; 0 for dates that do not fit.
    static func milliseconds(_ date: Date) -> Int64 {
        let value = (date.timeIntervalSince1970 * 1000).rounded()
        guard value.isFinite, abs(value) < 9.2e18 else { return 0 }
        return Int64(value)
    }
}
