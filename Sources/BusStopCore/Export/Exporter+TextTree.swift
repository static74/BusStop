import Foundation

extension Exporter {
    /// Plain-text tree used by the CLI's default output.
    ///
    /// ```
    /// MacBook Pro (14-inch, 2026, M5 Pro) · macOS 27.0
    /// Power: 96W USB-C Power Adapter · 20 V × 4.7 A · 61 W in · Charging · 82%
    /// ├─ Left Rear · MagSafe   96W USB-C Power Adapter   ↓ 61 W
    /// ├─ Left Front · USB-C   USB 3.2 Gen 2 @ 10 Gb/s   ↑ 4.5 W
    /// │  └─ Samsung T9 · 10 Gb/s · 4.5 W
    /// └─ Right Center · USB-C   (empty)
    /// ```
    ///
    /// Then, when present, sections for other devices, displays and
    /// diagnostics. The output is deterministic, has no colour codes and no
    /// trailing spaces, and ends with a newline.
    public static func textTree(_ snapshot: HostSnapshot) -> String {
        var lines: [String] = []
        let os = snapshot.machine.osVersion.trimmingCharacters(in: .whitespaces)
        var header = "\(TextTree.clean(snapshot.machine.name)) · macOS"
        if !os.isEmpty { header += " \(os)" }
        if snapshot.isDemo { header += " · demo" }
        lines.append(header)
        lines.append(TextTree.powerLine(snapshot.power))

        if snapshot.ports.isEmpty {
            lines.append("└─ No ports found")
        }
        for (index, port) in snapshot.ports.enumerated() {
            let isLast = index == snapshot.ports.count - 1
            lines.append((isLast ? "└─ " : "├─ ") + TextTree.portText(port))
            TextTree.appendDevices(port.devices, prefix: isLast ? "   " : "│  ", to: &lines)
        }

        if !snapshot.otherDevices.isEmpty {
            lines.append("")
            lines.append("Other devices")
            TextTree.appendDevices(snapshot.otherDevices, prefix: "", to: &lines)
        }

        if !snapshot.displays.isEmpty {
            lines.append("")
            lines.append("Displays")
            for (index, display) in snapshot.displays.enumerated() {
                let branch = index == snapshot.displays.count - 1 ? "└─ " : "├─ "
                lines.append(branch + TextTree.displayText(display, in: snapshot))
            }
        }

        if !snapshot.diagnostics.isEmpty {
            lines.append("")
            lines.append("Diagnostics")
            for (index, diagnostic) in snapshot.diagnostics.enumerated() {
                let branch = index == snapshot.diagnostics.count - 1 ? "└─ " : "├─ "
                lines.append(branch + "\(TextTree.severityText(diagnostic.severity)): \(TextTree.clean(diagnostic.title))")
            }
        }

        return lines.map(TextTree.trimTrailing).joined(separator: "\n") + "\n"
    }
}

/// Line builders for `Exporter.textTree`.
enum TextTree {
    /// Separator between the columns of a port line.
    static let gap = "   "

    /// "Power: 96W USB-C Power Adapter · 20 V × 4.7 A · 61 W in · Charging · 82%".
    static func powerLine(_ power: PowerSummary) -> String {
        var parts: [String] = []
        if let charger = power.charger {
            parts.append(clean(charger.displayName))
            if let mv = charger.millivolts, let ma = charger.milliamps, mv > 0, ma > 0 {
                parts.append(Format.contract(millivolts: mv, milliamps: ma))
            }
        }
        if let input = power.systemInputMilliwatts, input > 0 {
            parts.append("\(Format.power(milliwatts: input)) in")
        }
        if let battery = power.battery {
            parts.append(battery.statusText)
        }
        if power.portOutputMilliwatts > 0 {
            parts.append("\(Format.power(milliwatts: power.portOutputMilliwatts)) to ports")
        }
        if parts.isEmpty {
            parts.append(power.hasBattery ? "On battery" : "No power readings")
        }
        return "Power: " + parts.joined(separator: " · ")
    }

    /// "Left Front · USB-C   USB 3.2 Gen 2 @ 10 Gb/s   ↑ 4.5 W".
    static func portText(_ port: PhysicalPort) -> String {
        var columns = [clean(port.label.title)]
        if let link = port.link { columns.append(link.label) }
        if let charger = port.charger { columns.append(clean(charger.displayName)) }
        if let badge = powerBadge(port.power) { columns.append(badge) }
        if columns.count == 1 && port.devices.isEmpty {
            columns.append(port.isConnected ? "(connected)" : "(empty)")
        }
        return columns.joined(separator: gap)
    }

    /// "↑ 4.5 W" for power out, "↓ 61 W" for power in; nil when nothing flows.
    static func powerBadge(_ power: PortPower?) -> String? {
        guard let power, let mw = power.milliwatts, mw > 0 else { return nil }
        switch power.direction {
        case .output: return "↑ \(Format.power(milliwatts: mw))"
        case .input: return "↓ \(Format.power(milliwatts: mw))"
        case .none: return nil
        }
    }

    /// Appends one line per device, depth first, with box-drawing branches.
    static func appendDevices(_ devices: [DeviceNode], prefix: String, to lines: inout [String]) {
        for (index, device) in devices.enumerated() {
            let isLast = index == devices.count - 1
            lines.append(prefix + (isLast ? "└─ " : "├─ ") + deviceText(device))
            appendDevices(device.children, prefix: prefix + (isLast ? "   " : "│  "), to: &lines)
        }
    }

    /// "Samsung T9 · 10 Gb/s · 4.5 W".
    static func deviceText(_ device: DeviceNode) -> String {
        let name = clean(device.name)
        var parts = [name.isEmpty ? device.kind.displayName : name]
        if let rate = device.link?.rateLabel ?? device.link?.generation { parts.append(rate) }
        let milliwatts = device.rolledUpMilliwatts
        if milliwatts > 0 { parts.append(Format.power(milliwatts: milliwatts)) }
        return parts.joined(separator: " · ")
    }

    /// "Studio Display · 5120 × 2880 @ 60 Hz · Left Front · USB-C".
    static func displayText(_ display: DisplayInfo, in snapshot: HostSnapshot) -> String {
        let name = clean(display.name)
        var parts = [name.isEmpty ? "Display" : name]
        if let mode = display.modeDescription { parts.append(mode) }
        if display.isBuiltin {
            parts.append("built-in")
        } else if let key = display.portKey, let port = snapshot.port(key) {
            parts.append(clean(port.label.title))
        }
        return parts.joined(separator: " · ")
    }

    static func severityText(_ severity: DiagnosticSeverity) -> String {
        switch severity {
        case .critical: return "Critical"
        case .warning: return "Warning"
        case .info: return "Info"
        }
    }

    /// Text with control characters (including escape sequences) replaced by
    /// spaces and surrounding whitespace removed, so device-supplied names
    /// cannot break lines or inject terminal codes.
    static func clean(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { scalar -> Character in
            CharacterSet.controlCharacters.contains(scalar) ? " " : Character(scalar)
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }

    static func trimTrailing(_ line: String) -> String {
        var line = line
        while let last = line.last, last == " " || last == "\t" { line.removeLast() }
        return line
    }
}
