import AppKit
import BusStopCore
import SwiftUI

// Helpers shared by the topology window's pages, the inspector and the graph.

// MARK: - Text

/// Strings shared by the topology window's views.
enum WindowText {
    /// "1 device", "3 devices".
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    /// Window subtitle: "4 ports · 6 devices · 61 W in".
    static func summary(_ snapshot: HostSnapshot) -> String {
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
            let out = max(power.portOutputMilliwatts, power.usbAllocatedMilliwatts)
            if out > 0 { parts.append("\(Format.power(milliwatts: out)) out") }
        }
        return parts.joined(separator: " · ")
    }

    /// Rate for VoiceOver: "10 gigabits per second", or the generation when the rate is unknown.
    static func spokenRate(_ link: LinkInfo) -> String {
        guard let rate = link.rateLabel else { return link.generation }
        let spoken = rate
            .replacingOccurrences(of: "Gb/s", with: "gigabits per second")
            .replacingOccurrences(of: "Mb/s", with: "megabits per second")
            .replacingOccurrences(of: "kb/s", with: "kilobits per second")
        return "\(link.generation), \(spoken)"
    }

    /// Power for VoiceOver: "4.5 watts".
    static func spokenPower(_ milliwatts: Int) -> String {
        Format.power(milliwatts: milliwatts)
            .replacingOccurrences(of: " mW", with: " milliwatts")
            .replacingOccurrences(of: " W", with: " watts")
    }

    /// Roll-up for containers ("3 devices · 7.5 W"), nil for leaves and empty containers.
    static func rollUp(_ device: DeviceNode) -> String? {
        let descendants = device.descendantCount
        guard descendants > 0 else { return nil }
        let devices = count(descendants, "device", "devices")
        if device.power?.isSelfPowered == true { return "\(devices) · own power" }
        let watts = device.rolledUpMilliwatts
        return watts > 0 ? "\(devices) · \(Format.power(milliwatts: watts))" : devices
    }

    /// Second line for device rows and graph nodes: "Hub · 3 devices · 7.5 W", "Storage · 4.5 W".
    static func deviceSubtitle(_ device: DeviceNode) -> String {
        if let rollUp = rollUp(device) { return "\(device.kind.displayName) · \(rollUp)" }
        var parts = [device.kind.displayName]
        if let milliwatts = device.power?.allocatedMilliwatts, milliwatts > 0 {
            parts.append(Format.power(milliwatts: milliwatts))
        } else if let vendor = device.vendorName, !vendor.isEmpty {
            parts.append(vendor)
        }
        return parts.joined(separator: " · ")
    }

    /// Full VoiceOver description of a device.
    static func deviceAccessibility(_ device: DeviceNode, portTitle: String?, isDeparting: Bool = false) -> String {
        var parts = [device.name, device.kind.displayName]
        if let portTitle { parts.append("on \(portTitle)") }
        if isDeparting {
            parts.append("disconnected")
        } else if let link = device.link {
            parts.append("connected at \(spokenRate(link))")
        }
        if let rollUp = rollUp(device) {
            parts.append(rollUp.replacingOccurrences(of: " · ", with: ", "))
        } else if let milliwatts = device.power?.allocatedMilliwatts, milliwatts > 0 {
            parts.append(spokenPower(milliwatts))
        }
        return parts.joined(separator: ", ")
    }

    /// Full VoiceOver description of a port.
    static func portAccessibility(_ port: PhysicalPort) -> String {
        var parts = ["\(port.label.title) port"]
        if !port.isConnected {
            parts.append("empty")
        } else if let first = port.devices.first {
            let others = port.deviceCount - 1
            var text = "\(first.name) connected"
            if let link = first.link { text += " at \(spokenRate(link))" }
            if others > 0 { text += ", and \(count(others, "other device", "other devices"))" }
            parts.append(text)
        } else if let charger = port.charger {
            parts.append("\(charger.displayName) connected")
        } else {
            parts.append("connected")
        }
        if let reading = portPower(port) {
            let direction = reading.direction == .input ? "into the Mac" : "to devices"
            parts.append("\(spokenPower(reading.milliwatts)) \(direction)")
        }
        return parts.joined(separator: ", ")
    }

    /// The power figure to show on a port: measured or contract power first,
    /// then the sum of USB allocations.
    static func portPower(_ port: PhysicalPort) -> WindowPowerReading? {
        if let power = port.power, let milliwatts = power.milliwatts, milliwatts > 0, power.direction != .none {
            return WindowPowerReading(milliwatts: milliwatts, direction: power.direction, isMeasured: power.isMeasured)
        }
        if port.allocatedMilliwatts > 0 {
            return WindowPowerReading(milliwatts: port.allocatedMilliwatts, direction: .output, isMeasured: false)
        }
        return nil
    }

    /// The headline power figure for the host: input while charging, otherwise
    /// power delivered to accessories.
    static func hostPower(_ power: PowerSummary) -> WindowPowerReading? {
        if let input = power.systemInputMilliwatts, input > 0 {
            return WindowPowerReading(milliwatts: input, direction: .input, isMeasured: true)
        }
        if let contract = power.charger?.contractMilliwatts, contract > 0 {
            return WindowPowerReading(milliwatts: contract, direction: .input, isMeasured: false)
        }
        let measured = power.portOutputMilliwatts
        let allocated = power.usbAllocatedMilliwatts
        if measured > 0 || allocated > 0 {
            return WindowPowerReading(milliwatts: max(measured, allocated), direction: .output,
                                      isMeasured: measured >= allocated)
        }
        return nil
    }

    static func yesNo(_ value: Bool?) -> String {
        guard let value else { return "Unknown" }
        return value ? "Yes" : "No"
    }

    /// Human name of a power figure's source.
    static func powerSource(_ source: PowerReadingSource) -> String {
        switch source {
        case .smc: return "Measured (SMC)"
        case .powerOutDetails: return "Measured (battery controller)"
        case .pdContract: return "USB-PD contract"
        case .telemetry: return "Power telemetry"
        case .usbAllocation: return "USB allocation (budget)"
        }
    }

    static func powerDirection(_ direction: PowerDirection) -> String {
        switch direction {
        case .input: return "Into the Mac"
        case .output: return "Out to devices"
        case .none: return "None"
        }
    }

    static func labelSource(_ source: LabelSource) -> String {
        switch source {
        case .user: return "Your name"
        case .catalog: return "Model catalogue"
        case .catalogRank: return "Model catalogue (by order)"
        case .generic: return "Generic"
        }
    }

    static func bus(_ bus: DeviceBus) -> String {
        switch bus {
        case .usb: return "USB"
        case .thunderbolt: return "Thunderbolt / USB4"
        case .displayPort: return "DisplayPort"
        case .power: return "Power"
        case .other: return "Other"
        }
    }

    static func eventKind(_ kind: ConnectionEvent.Kind) -> String {
        switch kind {
        case .deviceConnected: return "Device connected"
        case .deviceDisconnected: return "Device disconnected"
        case .linkChanged: return "Link speed changed"
        case .chargerConnected: return "Charger connected"
        case .chargerDisconnected: return "Charger disconnected"
        case .displayConnected: return "Display connected"
        case .displayDisconnected: return "Display disconnected"
        case .diagnosticRaised: return "Diagnostic raised"
        }
    }

    static func eventKindSymbol(_ kind: ConnectionEvent.Kind) -> String {
        switch kind {
        case .deviceConnected: return "arrow.down.right.circle"
        case .deviceDisconnected: return "arrow.up.left.circle"
        case .linkChanged: return "speedometer"
        case .chargerConnected: return "bolt.circle"
        case .chargerDisconnected: return "bolt.slash.circle"
        case .displayConnected: return "display"
        case .displayDisconnected: return "display.trianglebadge.exclamationmark"
        case .diagnosticRaised: return "exclamationmark.triangle"
        }
    }
}

/// A power figure ready for a `PowerBadge`.
struct WindowPowerReading: Equatable {
    var milliwatts: Int
    var direction: PowerDirection
    var isMeasured: Bool
}

// MARK: - Search

/// Case-insensitive matching used by the window's search field.
nonisolated enum TopologySearch {
    static func normalized(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func port(_ port: PhysicalPort, matches query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = [port.label.title, port.label.shortTitle, port.registryName, port.kind.displayName,
                      port.capabilityDescription ?? "", port.charger?.displayName ?? ""]
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func device(_ device: DeviceNode, matches query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = [device.name, device.vendorName ?? "", device.kind.displayName,
                      device.vendorProductIDString ?? "", device.serialNumber ?? ""]
        return fields.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    static func display(_ display: DisplayInfo, matches query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return display.name.localizedCaseInsensitiveContains(query) || "display".localizedCaseInsensitiveContains(query)
    }

    /// The device with only the branches that match (a match keeps its whole
    /// subtree), or nil when nothing in the tree matches.
    static func prune(_ device: DeviceNode, query: String) -> DeviceNode? {
        if query.isEmpty || self.device(device, matches: query) { return device }
        let children = device.children.compactMap { prune($0, query: query) }
        guard !children.isEmpty else { return nil }
        var copy = device
        copy.children = children
        return copy
    }
}

// MARK: - Selection tags

/// String tags for `StoreSelection`, used by lists and tables whose selection
/// type must be a plain value.
enum SelectionTag {
    static let host = "host"

    static func port(_ key: PortKey) -> String { "port:\(key)" }
    static func device(_ id: String) -> String { "device:\(id)" }
    static func display(_ id: String) -> String { "display:\(id)" }

    static func string(for selection: StoreSelection?) -> String? {
        switch selection {
        case .host?: return host
        case .port(let key)?: return port(key)
        case .device(let id)?: return device(id)
        case .display(let id)?: return display(id)
        case nil: return nil
        }
    }

    static func selection(for tag: String?) -> StoreSelection? {
        guard let tag else { return nil }
        if tag == host { return .host }
        if let rest = tag.dropPrefix("port:") { return PortKey(rest).map(StoreSelection.port) }
        if let rest = tag.dropPrefix("device:") { return .device(rest) }
        if let rest = tag.dropPrefix("display:") { return .display(rest) }
        return nil
    }
}

private extension String {
    /// The remainder after `prefix`, or nil when the string does not start with it.
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

// MARK: - Layout scale

extension TextSizeSetting {
    /// How much larger graph nodes get with the Text Size setting.
    var graphScale: CGFloat {
        switch self {
        case .small: return 0.94
        case .medium: return 1
        case .large: return 1.08
        case .extraLarge: return 1.18
        }
    }
}

// MARK: - Shared views

/// Large page title used at the top of every detail page.
struct WindowDetailHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.title2, design: .default).weight(.bold))
                    .foregroundStyle(Lagoon.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(Lagoon.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension WindowDetailHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Shown in the detail area until the first capture arrives.
struct WindowLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Reading ports…")
                .font(Lagoon.titleFont)
                .foregroundStyle(Lagoon.textPrimary)
            Text("Bus Stop is asking macOS what is plugged in.")
                .font(.callout)
                .foregroundStyle(Lagoon.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small borderless button that copies a value to the clipboard.
struct WindowCopyButton: View {
    var value: String
    var help: String = "Copy"
    @State private var didCopy = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            didCopy = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(didCopy ? Lagoon.accent : Lagoon.textTertiary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Capsule count badge, tinted (used in the sidebar and page headers).
struct WindowCountBadge: View {
    var count: Int
    var color: Color = Lagoon.accent

    var body: some View {
        Text("\(count)")
            .font(Lagoon.chipFont)
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.16)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.75))
    }
}
