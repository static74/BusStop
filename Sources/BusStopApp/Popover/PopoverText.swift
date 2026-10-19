import AppKit
import BusStopCore
import SwiftUI

/// Text helpers for the popover: counts, VoiceOver phrasing and clipboard text.
enum PopoverText {
    /// "1 device", "3 devices".
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    /// "4 ports · 6 devices · 61 W in".
    static func summary(for snapshot: HostSnapshot) -> String {
        var parts = [
            count(snapshot.ports.count, "port", "ports"),
            count(snapshot.deviceCount, "device", "devices"),
        ]
        let power = snapshot.power
        if let input = power.systemInputMilliwatts, input > 0 {
            parts.append("\(Format.power(milliwatts: input)) in")
        } else if let contract = power.charger?.contractMilliwatts, contract > 0 {
            parts.append("\(Format.power(milliwatts: contract)) in")
        } else {
            var out = max(power.portOutputMilliwatts, power.usbAllocatedMilliwatts)
            if out == 0 { out = unattributedUSBMilliwatts(snapshot) }
            if out > 0 { parts.append("\(Format.power(milliwatts: out)) out") }
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// USB power the Mac allocates to devices it could not tie to a port: the
    /// USB devices under Other devices that it powers itself (not through a
    /// Thunderbolt dock), stopping at self-powered hubs.
    static func unattributedUSBMilliwatts(_ snapshot: HostSnapshot) -> Int {
        snapshot.otherDevices
            .filter { $0.bus == .usb && !$0.isTunneled }
            .reduce(0) { $0 + $1.rolledUpMilliwatts }
    }

    /// The power figure for the menu bar: `PowerSummary.headlineMilliwatts`,
    /// or what unattributed USB devices draw when the ports report nothing.
    static func headlineMilliwatts(for snapshot: HostSnapshot) -> Int? {
        if let headline = snapshot.power.headlineMilliwatts { return headline }
        let unattributed = unattributedUSBMilliwatts(snapshot)
        return unattributed > 0 ? unattributed : nil
    }

    /// The compact row's middle text: "Samsung T9", "3 devices", the
    /// charger's name, "Connected" or "Nothing connected". `devices` includes
    /// ghosts (`PortStore.devicesWithGhosts(on:)`), so a device that just left
    /// keeps its line until its ghost goes. "N devices" counts every level,
    /// like `PhysicalPort.deviceCount`.
    static func compactSummary(_ port: PhysicalPort, devices: [DeviceNode]) -> String {
        if devices.count == 1, let device = devices.first { return device.name }
        if devices.count > 1 {
            return count(devices.reduce(0) { $0 + 1 + $1.descendantCount }, "device", "devices")
        }
        if let charger = port.charger { return charger.displayName }
        return port.isConnected ? "Connected" : "Nothing connected"
    }

    /// "3 devices · 7.5 W" for hubs and docks.
    static func rollUp(for device: DeviceNode) -> String? {
        guard !device.children.isEmpty else { return nil }
        var text = count(device.descendantCount, "device", "devices")
        let milliwatts = device.rolledUpMilliwatts
        if milliwatts > 0 { text += " \u{00B7} " + Format.power(milliwatts: milliwatts) }
        return text
    }

    // MARK: VoiceOver

    /// "Left Front USB-C" from "Left Front · USB-C".
    static func spokenPortTitle(_ label: PortLabel) -> String {
        label.title.replacingOccurrences(of: " \u{00B7} ", with: " ")
    }

    /// "10 gigabits per second".
    static func spokenRate(_ link: LinkInfo?) -> String? {
        guard let rate = link?.rateLabel else { return nil }
        let units: [(String, String)] = [
            (" Gb/s", " gigabits per second"),
            (" Mb/s", " megabits per second"),
            (" kb/s", " kilobits per second"),
            (" b/s", " bits per second"),
        ]
        for (suffix, spoken) in units where rate.hasSuffix(suffix) {
            return String(rate.dropLast(suffix.count)) + spoken
        }
        return rate
    }

    /// "4.5 watts", "120 milliwatts".
    static func spokenPower(milliwatts: Int) -> String {
        let text = Format.power(milliwatts: milliwatts)
        if text.hasSuffix(" mW") { return String(text.dropLast(3)) + " milliwatts" }
        if text.hasSuffix(" W") { return String(text.dropLast(2)) + " watts" }
        return text
    }

    /// "61 watts in", "up to 4.5 watts" (a budget or contract, not a measurement),
    /// or nil when the port draws or gives nothing.
    static func spokenPortPower(_ power: PortPower?) -> String? {
        guard let power, let milliwatts = power.milliwatts, milliwatts > 0 else { return nil }
        let phrase = (power.isMeasured ? "" : "up to ") + spokenPower(milliwatts: milliwatts)
        return power.direction == .input ? phrase + " in" : phrase
    }

    /// "Left Front USB-C port, Samsung T9 connected at 10 gigabits per second, 4.5 watts",
    /// then ", pinned to the menu bar" when `isPinned`.
    static func portAccessibilityLabel(_ port: PhysicalPort, isPinned: Bool) -> String {
        var parts = ["\(spokenPortTitle(port.label)) port"]
        if port.devices.count == 1, let device = port.devices.first {
            var phrase = "\(device.name) connected"
            if let rate = spokenRate(device.link) { phrase += " at \(rate)" }
            parts.append(phrase)
            if !device.children.isEmpty {
                parts.append(count(device.descendantCount, "more device", "more devices") + " behind it")
            }
        } else if port.devices.count > 1 {
            parts.append(count(port.deviceCount, "device", "devices") + " connected")
        } else if let charger = port.charger {
            parts.append("\(charger.displayName) connected")
        } else if port.isConnected {
            parts.append("connected")
        } else {
            parts.append("nothing connected")
        }
        if let power = spokenPortPower(port.power) { parts.append(power) }
        if isPinned { parts.append("pinned to the menu bar") }
        return parts.joined(separator: ", ")
    }

    /// The VoiceOver label for one device row.
    static func deviceAccessibilityLabel(_ device: DeviceNode, port: PhysicalPort?, depth: Int,
                                         isDeparting: Bool) -> String {
        var parts: [String] = []
        var phrase = device.name
        if depth == 0, let port {
            phrase = "\(spokenPortTitle(port.label)) port, \(device.name)"
        }
        if isDeparting {
            phrase += " disconnected"
            return phrase
        }
        phrase += " connected"
        if let rate = spokenRate(device.link) { phrase += " at \(rate)" }
        parts.append(phrase)
        if let milliwatts = device.power?.allocatedMilliwatts, milliwatts > 0 {
            parts.append(spokenPower(milliwatts: milliwatts))
        }
        if !device.children.isEmpty {
            var rollUp = count(device.descendantCount, "device", "devices") + " behind it"
            if device.rolledUpMilliwatts > 0 {
                rollUp += ", " + spokenPower(milliwatts: device.rolledUpMilliwatts) + " in total"
            }
            parts.append(rollUp)
        }
        if let builtIn = device.internalParts, !builtIn.isEmpty {
            parts.append(count(builtIn.count, "built-in part", "built-in parts"))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Clipboard

    /// Multi-line description of a device for "Copy Details".
    static func details(for device: DeviceNode, port: PhysicalPort?, redactSerials: Bool) -> String {
        var lines = [device.name]
        lines.append("Kind: \(device.kind.displayName)")
        lines.append("Port: \(port?.label.title ?? "Not attributed to a port")")
        if let link = device.link { lines.append("Link: \(link.label)") }
        if let milliwatts = device.power?.allocatedMilliwatts, milliwatts > 0 {
            lines.append("Power: \(Format.power(milliwatts: milliwatts))")
        }
        if !device.children.isEmpty, let rollUp = rollUp(for: device) {
            lines.append("Downstream: \(rollUp)")
        }
        if let parts = device.internalParts, !parts.isEmpty {
            lines.append("Built in: \(parts.map(\.name).joined(separator: ", "))")
        }
        if let vendor = device.vendorName { lines.append("Vendor: \(vendor)") }
        if let ids = device.vendorProductIDString { lines.append("IDs: \(ids)") }
        if let version = device.usbVersion { lines.append("USB version: \(version)") }
        if let location = device.locationID { lines.append("Location ID: \(Format.hex8(location))") }
        if let serial = device.serialNumber, !serial.isEmpty, !redactSerials {
            lines.append("Serial: \(serial)")
        }
        lines.append("ID: \(redactSerials ? Exporter.redactedID(device.id) : device.id)")
        return lines.joined(separator: "\n")
    }

    static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

extension View {
    /// Reports this view's height whenever it changes.
    func onHeightChange(_ action: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            action(height)
        }
    }
}
