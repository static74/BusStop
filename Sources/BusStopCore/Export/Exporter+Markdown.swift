import Foundation

extension Exporter {
    /// A Markdown report: machine, power summary, one section per port with a
    /// device tree, displays, diagnostics.
    ///
    /// Serial numbers are shown as "REDACTED" when `redact` is true. Raw
    /// property bags are not part of the report.
    public static func markdown(_ snapshot: HostSnapshot, redact: Bool = true) -> String {
        var report = MarkdownReport(redact: redact)
        report.render(snapshot)
        return report.text
    }
}

/// Builds the Markdown report line by line.
private struct MarkdownReport {
    let redact: Bool
    private(set) var lines: [String] = []

    init(redact: Bool) {
        self.redact = redact
    }

    var text: String {
        // Collapse runs of blank lines and end with exactly one newline.
        var output: [String] = []
        for line in lines.map(Self.trimTrailing) where !(line.isEmpty && (output.last?.isEmpty ?? true)) {
            output.append(line)
        }
        while output.last?.isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n") + "\n"
    }

    mutating func render(_ snapshot: HostSnapshot) {
        header(snapshot)
        power(snapshot)
        ports(snapshot)
        otherDevices(snapshot)
        displays(snapshot)
        diagnostics(snapshot)
        notes(snapshot)
    }

    // MARK: Sections

    private mutating func header(_ snapshot: HostSnapshot) {
        let machine = snapshot.machine
        lines.append("# \(Self.escape(machine.name))")
        lines.append("")
        var facts = ["Captured \(Self.isoDate(snapshot.capturedAt))"]
        if !machine.osVersion.isEmpty { facts.append("macOS \(machine.osVersion)") }
        facts.append(machine.model)
        if let chip = machine.chip, !chip.isEmpty { facts.append(chip) }
        if snapshot.isDemo { facts.append("demo data") }
        lines.append(facts.map(Self.escape).joined(separator: " · "))
        lines.append("")
        lines.append(Self.summary(snapshot))
        lines.append("")
    }

    private mutating func power(_ snapshot: HostSnapshot) {
        let power = snapshot.power
        lines.append("## Power")
        lines.append("")
        var facts: [String] = []
        if let charger = power.charger {
            var name = "Charger: \(Self.escape(charger.displayName))"
            if let maker = charger.manufacturer, !maker.isEmpty { name += " (\(Self.escape(maker)))" }
            if let key = charger.portKey, let port = snapshot.port(key) { name += " on \(Self.escape(port.label.title))" }
            facts.append(name)
            if let watts = charger.ratedWatts, watts > 0 { facts.append("Rated: \(watts) W") }
            if let mv = charger.millivolts, let ma = charger.milliamps, mv > 0, ma > 0 {
                facts.append("Active contract: \(Format.contract(millivolts: mv, milliamps: ma)) "
                    + "(\(Format.power(milliwatts: mv * ma / 1000)))")
            }
            if let family = charger.familyDescription, !family.isEmpty { facts.append("Type: \(Self.escape(family))") }
            if charger.isWireless { facts.append("Wireless: yes") }
            if let serial = charger.serialNumber { facts.append("Serial number: \(serialText(serial))") }
        } else {
            facts.append("Charger: none")
        }
        if let battery = power.battery { facts.append("Battery: \(battery.statusText)") }
        if let input = power.systemInputMilliwatts { facts.append("System input: \(Format.power(milliwatts: input))") }
        if let load = power.systemLoadMilliwatts { facts.append("System load: \(Format.power(milliwatts: load))") }
        facts.append("Delivered to ports: \(Format.power(milliwatts: power.portOutputMilliwatts))")
        facts.append("USB allocations: \(Format.power(milliwatts: power.usbAllocatedMilliwatts))")
        lines += facts.map { "- \($0)" }
        lines.append("")

        if let profiles = power.charger?.profiles, !profiles.isEmpty {
            lines.append("| Profile | Voltage × current | Max power | Active |")
            lines.append("|---:|---|---:|:---:|")
            for profile in profiles.sorted(by: { $0.index < $1.index }) {
                lines.append("| \(profile.index) | \(profile.label) | \(Format.power(milliwatts: profile.maxMilliwatts)) | "
                    + "\(profile.isActive ? "yes" : "") |")
            }
            lines.append("")
        }
    }

    private mutating func ports(_ snapshot: HostSnapshot) {
        lines.append("## Ports")
        lines.append("")
        guard !snapshot.ports.isEmpty else {
            lines.append("No ports were reported.")
            lines.append("")
            return
        }
        for port in snapshot.ports {
            lines.append("### \(Self.escape(port.label.title))")
            lines.append("")
            var facts: [String] = []
            facts.append("Status: \(port.isConnected ? "connected" : "empty")")
            if let capability = port.capabilityDescription, !capability.isEmpty {
                facts.append("Capability: \(Self.escape(capability))")
            }
            if !port.supportedTransports.isEmpty {
                facts.append("Supports: " + port.supportedTransports.sorted().map(\.displayName).joined(separator: ", "))
            }
            if let link = port.link { facts.append("Link: \(Self.escape(link.label))") }
            if !port.activeTransports.isEmpty {
                facts.append("Active: " + port.activeTransports.map(Self.transportText).joined(separator: ", "))
            }
            if let power = port.power, let text = Self.portPowerText(power) { facts.append("Power: \(text)") }
            if let charger = port.charger { facts.append("Charger: \(Self.escape(charger.displayName))") }
            if let cable = port.cable, let text = Self.cableText(cable) { facts.append("Cable: \(text)") }
            if port.liquidDetected { facts.append("Liquid detected: yes") }
            facts.append("Registry name: `\(port.registryName)`")
            lines += facts.map { "- \($0)" }
            if port.devices.isEmpty {
                lines.append("- Devices: none")
            } else {
                lines.append("- Devices:")
                for device in port.devices { deviceTree(device, depth: 1) }
            }
            lines.append("")
        }
    }

    private mutating func otherDevices(_ snapshot: HostSnapshot) {
        guard !snapshot.otherDevices.isEmpty else { return }
        lines.append("## Other devices")
        lines.append("")
        lines.append("Devices that could not be tied to a port.")
        lines.append("")
        for device in snapshot.otherDevices { deviceTree(device, depth: 0) }
        lines.append("")
    }

    private mutating func displays(_ snapshot: HostSnapshot) {
        guard !snapshot.displays.isEmpty else { return }
        lines.append("## Displays")
        lines.append("")
        lines.append("| Display | Mode | Port | Link | Serial number |")
        lines.append("|---|---|---|---|---|")
        for display in snapshot.displays {
            var name = Self.escape(display.name.isEmpty ? "Display" : display.name)
            if display.isBuiltin { name += " (built-in)" }
            let port = display.portKey.flatMap { snapshot.port($0) }.map { Self.escape($0.label.title) } ?? ""
            let serial = display.serialNumber.map { serialText(String($0)) } ?? ""
            lines.append("| \(name) | \(display.modeDescription ?? "") | \(port) | "
                + "\(display.link.map { Self.escape($0.label) } ?? "") | \(serial) |")
        }
        lines.append("")
    }

    private mutating func diagnostics(_ snapshot: HostSnapshot) {
        lines.append("## Diagnostics")
        lines.append("")
        guard !snapshot.diagnostics.isEmpty else {
            lines.append("No problems found.")
            lines.append("")
            return
        }
        for diagnostic in snapshot.diagnostics {
            lines.append("- **\(Self.severityText(diagnostic.severity)):** \(Self.escape(diagnostic.title))")
            lines.append("  - \(Self.escape(diagnostic.detail))")
            if let suggestion = diagnostic.suggestion, !suggestion.isEmpty {
                lines.append("  - Suggestion: \(Self.escape(suggestion))")
            }
        }
        lines.append("")
    }

    private mutating func notes(_ snapshot: HostSnapshot) {
        guard !snapshot.captureNotes.isEmpty else { return }
        lines.append("## Capture notes")
        lines.append("")
        lines += snapshot.captureNotes.map { "- \(Self.escape($0))" }
        lines.append("")
    }

    // MARK: Devices

    /// One bullet per device, nested two spaces per level.
    private mutating func deviceTree(_ device: DeviceNode, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)- \(deviceText(device))")
        for child in device.children { deviceTree(child, depth: depth + 1) }
    }

    private func deviceText(_ device: DeviceNode) -> String {
        let name = device.name.trimmingCharacters(in: .whitespaces)
        var parts = ["**\(Self.escape(name.isEmpty ? device.kind.displayName : name))** (\(device.kind.displayName))"]
        if let link = device.link { parts.append(Self.escape(link.label)) }
        let milliwatts = device.rolledUpMilliwatts
        if milliwatts > 0 { parts.append("\(Format.power(milliwatts: milliwatts)) allocated") }
        if device.power?.isSelfPowered == true { parts.append("self-powered") }
        if !device.children.isEmpty {
            let count = device.descendantCount
            parts.append(count == 1 ? "1 device" : "\(count) devices")
        }
        if let ids = device.vendorProductIDString { parts.append("`\(ids)`") }
        if device.isTunneled { parts.append("tunnelled") }
        if let serial = device.serialNumber { parts.append("serial \(serialText(serial))") }
        return parts.joined(separator: " · ")
    }

    private func serialText(_ serial: String) -> String {
        redact ? Exporter.redactedText : Self.escape(serial)
    }

    // MARK: Formatting helpers

    /// "3 ports · 2 connected · 5 devices · 61 W in".
    static func summary(_ snapshot: HostSnapshot) -> String {
        var parts = [
            plural(snapshot.ports.count, "port"),
            "\(snapshot.connectedPorts.count) connected",
            plural(snapshot.deviceCount, "device"),
        ]
        if let input = snapshot.power.systemInputMilliwatts, input > 0 {
            parts.append("\(Format.power(milliwatts: input)) in")
        } else if snapshot.power.portOutputMilliwatts > 0 {
            parts.append("\(Format.power(milliwatts: snapshot.power.portOutputMilliwatts)) out")
        }
        return parts.joined(separator: " · ")
    }

    static func plural(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    static func transportText(_ transport: TransportInfo) -> String {
        var text = transport.kind.displayName
        if let rate = transport.link?.rateLabel { text += " \(rate)" }
        if transport.isTunneled { text += " (tunnelled)" }
        return text
    }

    static func portPowerText(_ power: PortPower) -> String? {
        guard let mw = power.milliwatts else { return nil }
        let value = Format.power(milliwatts: mw)
        let basis: String
        switch power.source {
        case .smc, .powerOutDetails, .telemetry: basis = "measured"
        case .pdContract: basis = "contract"
        case .usbAllocation: basis = "allocated"
        }
        switch power.direction {
        case .input: return "↓ \(value) in (\(basis))"
        case .output: return "↑ \(value) out (\(basis))"
        case .none: return nil
        }
    }

    static func cableText(_ cable: CableInfo) -> String? {
        var parts: [String] = []
        if let type = cable.typeDescription, !type.isEmpty {
            parts.append(escape(type))
        } else if let active = cable.isActive {
            parts.append(active ? "Active cable" : "Passive cable")
        }
        if cable.isOptical == true { parts.append("optical") }
        if let speed = cable.speedDescription, !speed.isEmpty { parts.append(escape(speed)) }
        if let current = cable.currentRatingMilliamps { parts.append("rated \(Format.current(milliamps: current))") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func severityText(_ severity: DiagnosticSeverity) -> String {
        switch severity {
        case .critical: return "Critical"
        case .warning: return "Warning"
        case .info: return "Info"
        }
    }

    static func isoDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// Escapes characters that Markdown would treat as formatting.
    static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\`*_[]|<>".contains(character) { result.append("\\") }
            if character == "\n" || character == "\r" {
                result.append(" ")
            } else {
                result.append(character)
            }
        }
        return result
    }

    static func trimTrailing(_ line: String) -> String {
        var line = line
        while let last = line.last, last == " " || last == "\t" { line.removeLast() }
        return line
    }
}
