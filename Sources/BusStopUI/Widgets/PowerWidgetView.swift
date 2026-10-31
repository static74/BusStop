import BusStopCore
import SwiftUI
import WidgetKit

/// The Power widget. Large: the power source and its USB-PD contract, the
/// headline figures (in, battery, what the Mac uses, out) and the last
/// hour. Extra Large adds the power through each port and the last 24 hours.
public struct PowerWidgetView: View {
    let entry: WidgetTimeline.Entry
    let family: WidgetFamily

    public init(entry: WidgetTimeline.Entry, family: WidgetFamily) {
        self.entry = entry
        self.family = family
    }

    public var body: some View {
        WidgetChrome("Power", symbol: "bolt.fill", entry: entry) { payload in
            if family == .systemExtraLarge {
                HStack(alignment: .top, spacing: 20) {
                    PowerWidgetSummary(payload: payload)
                    VStack(alignment: .leading, spacing: 12) {
                        PowerWidgetPorts(snapshot: payload.snapshot)
                        PowerWidgetChartSection(payload: payload, range: .day)
                    }
                }
            } else {
                PowerWidgetSummary(payload: payload)
            }
        }
        .widgetURL(BusStopLink.page(.power).url)
    }
}

/// The Large widget's content, and the Extra Large widget's left half.
struct PowerWidgetSummary: View {
    var payload: WidgetPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PowerWidgetSourceRow(source: PowerWidgetText.source(payload.snapshot))
            PowerWidgetFigures(figures: PowerWidgetText.figures(payload.snapshot))
            PowerWidgetChartSection(payload: payload, range: .hour)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Text

/// The words and numbers the Power widget shows, kept apart from the views
/// so tests can check them.
enum PowerWidgetText {
    struct Source: Equatable {
        var symbol: String
        var title: String
        var detail: String
        var isCharger: Bool
    }

    struct Figure: Equatable, Identifiable {
        var label: String
        var symbol: String
        var value: String
        var detail: String
        var id: String { label }
    }

    /// The charger and its contract ("28 V × 5 A · Left Rear"), or what
    /// powers the Mac without one.
    static func source(_ snapshot: HostSnapshot) -> Source {
        let power = snapshot.power
        if let charger = power.charger {
            var parts: [String] = []
            if let millivolts = charger.millivolts, let milliamps = charger.milliamps, millivolts > 0, milliamps > 0 {
                parts.append(Format.contract(millivolts: millivolts, milliamps: milliamps))
            } else if let profile = charger.activeProfile {
                parts.append(profile.label)
            }
            if let key = charger.portKey, let port = snapshot.port(key) { parts.append(port.label.shortTitle) }
            return Source(symbol: charger.isWireless ? "bolt.circle" : "bolt.fill", title: charger.displayName,
                          detail: parts.isEmpty ? "No USB-PD contract reported" : parts.joined(separator: " \u{00B7} "),
                          isCharger: true)
        }
        if power.hasBattery || power.battery != nil || snapshot.machine.isLaptop {
            return Source(symbol: "powerplug", title: "No charger", detail: "Running on battery", isCharger: false)
        }
        return Source(symbol: "powerplug.fill", title: "Mains power", detail: "No battery or USB-PD charger",
                      isCharger: false)
    }

    /// The headline figures, most important first: power in, the battery,
    /// what the Mac uses and what the ports give out. A desktop that
    /// reports none of the first three gets the USB budget instead.
    static func figures(_ snapshot: HostSnapshot) -> [Figure] {
        let power = snapshot.power
        var figures: [Figure] = []
        let measuredInput = power.systemInputMilliwatts.flatMap { $0 > 0 ? $0 : nil }
        if let input = measuredInput ?? power.charger?.contractMilliwatts {
            figures.append(Figure(label: "In", symbol: "arrow.down", value: Format.power(milliwatts: input),
                                  detail: measuredInput == nil ? "contract" : "from charger"))
        }
        if let battery = power.battery {
            figures.append(Figure(label: "Battery", symbol: batterySymbol(battery),
                                  value: battery.percent.map { "\($0)%" } ?? "\u{2014}",
                                  detail: batteryState(battery)))
        }
        if let load = power.systemLoadMilliwatts, load > 0 {
            let symbol = snapshot.machine.isLaptop ? "laptopcomputer" : "desktopcomputer"
            figures.append(Figure(label: "Load", symbol: symbol, value: Format.power(milliwatts: load),
                                  detail: "used by Mac"))
        }
        let out = accessoryDraw(snapshot)
        figures.append(Figure(label: "Out", symbol: "arrow.up", value: Format.power(milliwatts: out.milliwatts),
                              detail: out.isMeasured || out.milliwatts == 0 ? "to devices" : "allocated"))
        if figures.count == 1, out.isMeasured, power.usbAllocatedMilliwatts > 0 {
            figures.append(Figure(label: "USB budget", symbol: "cable.connector",
                                  value: Format.power(milliwatts: power.usbAllocatedMilliwatts), detail: "allocated"))
        }
        return figures
    }

    /// "Charging", "Charged", "Not charging" or "On battery", as `BatteryInfo.statusText` without the percentage.
    static func batteryState(_ battery: BatteryInfo) -> String {
        if battery.isFullyCharged && battery.externalConnected { return "Charged" }
        if battery.isCharging { return "Charging" }
        return battery.externalConnected ? "Not charging" : "On battery"
    }

    static func batterySymbol(_ battery: BatteryInfo) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percent ?? 50 {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// Power delivered to accessories: measured port output when known, else
    /// the USB budget, else what unattributed USB devices are allocated (as
    /// the popover's power strip counts it).
    static func accessoryDraw(_ snapshot: HostSnapshot) -> (milliwatts: Int, isMeasured: Bool) {
        let power = snapshot.power
        if power.portOutputMilliwatts > 0 { return (power.portOutputMilliwatts, true) }
        if power.usbAllocatedMilliwatts > 0 { return (power.usbAllocatedMilliwatts, false) }
        return (PopoverText.unattributedUSBMilliwatts(snapshot), false)
    }

    /// Ports with power flowing through them, in physical order.
    static func poweredPorts(_ snapshot: HostSnapshot) -> [PhysicalPort] {
        snapshot.ports.filter { ($0.power?.milliwatts ?? 0) > 0 && $0.power?.direction != PowerDirection.none }
    }
}

// MARK: - Source and figures

/// What powers the Mac: the charger's name and contract, or the battery or mains.
struct PowerWidgetSourceRow: View {
    var source: PowerWidgetText.Source

    var body: some View {
        let color = source.isCharger ? Lagoon.powerIn : Lagoon.textSecondary
        HStack(spacing: 10) {
            Image(systemName: source.symbol)
                .lagoonFont(size: 14, weight: .semibold)
                .foregroundStyle(color)
                .widgetAccentable()
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title)
                    .lagoonFont(.headline, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(source.detail)
                    .lagoonFont(.caption, monospacedDigits: true)
                    .foregroundStyle(Lagoon.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The headline figures side by side, each a label, a large value and a detail line.
struct PowerWidgetFigures: View {
    var figures: [PowerWidgetText.Figure]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(figures) { figure in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: figure.symbol)
                            .lagoonFont(size: 9, weight: .bold)
                            .foregroundStyle(Lagoon.accent)
                            .widgetAccentable()
                        Text(figure.label)
                            .lagoonFont(.caption, weight: .semibold)
                            .foregroundStyle(Lagoon.textSecondary)
                    }
                    Text(figure.value)
                        .lagoonFont(size: 19, weight: .semibold, design: .rounded, monospacedDigits: true)
                    Text(figure.detail)
                        .lagoonFont(.caption)
                        .foregroundStyle(Lagoon.textTertiary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Lagoon.well))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Ports

/// The Extra Large widget's list of ports with power flowing through them.
struct PowerWidgetPorts: View {
    var snapshot: HostSnapshot
    /// Rows that fit above the day chart.
    static let rowLimit = 3

    var body: some View {
        let ports = PowerWidgetText.poweredPorts(snapshot)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Per port")
                Spacer(minLength: 4)
                if ports.count > Self.rowLimit { Text("\(ports.count - Self.rowLimit) more") }
            }
            .lagoonFont(.caption, weight: .semibold)
            .foregroundStyle(Lagoon.textSecondary)
            if ports.isEmpty {
                Text("No port is giving or taking power.")
                    .lagoonFont(.callout)
                    .foregroundStyle(Lagoon.textTertiary)
            } else {
                ForEach(ports.prefix(Self.rowLimit)) { port in
                    PowerWidgetPortRow(port: port)
                }
            }
        }
    }
}

/// One port: its icon, name, what is on it and the watts through it.
struct PowerWidgetPortRow: View {
    var port: PhysicalPort

    var body: some View {
        HStack(spacing: 8) {
            PortIcon(kind: port.kind, isActive: true, size: 24)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(port.label.title)
                    .lagoonFont(.callout, weight: .semibold)
                Text(PopoverText.compactSummary(port, devices: port.devices))
                    .lagoonFont(.caption)
                    .foregroundStyle(Lagoon.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            if let power = port.power, let milliwatts = power.milliwatts {
                PowerBadge(milliwatts: milliwatts, direction: power.direction, isMeasured: power.isMeasured)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PopoverText.portAccessibilityLabel(port, isPinned: false))
    }
}
