import BusStopCore
import SwiftUI

/// The Power page: totals, the charger and its profiles, the battery, and
/// power over time for the system and for each port.
struct PowerDetailView: View {
    var store: PortStore

    var body: some View {
        let snapshot = store.snapshot
        let power = snapshot.power
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WindowDetailHeader(title: "Power", subtitle: subtitle(power))

                PowerTotalsRow(power: power)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)],
                    alignment: .leading,
                    spacing: 16
                ) {
                    PowerChargerCard(power: power, portTitle: chargerPortTitle(snapshot))
                    if power.hasBattery || power.battery != nil {
                        PowerBatteryCard(battery: power.battery)
                    }
                }

                SystemPowerChartCard(
                    history: store.history,
                    load: SystemLoadRecorder.shared.series(for: store.history, current: snapshot)
                )
                PortPowerChartCard(history: store.history) { key in
                    snapshot.port(key)?.label.title ?? "Port \(key)"
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func subtitle(_ power: PowerSummary) -> String {
        if let reading = WindowText.hostPower(power) {
            let direction = reading.direction == .input ? "into the Mac" : "out to devices"
            return "\(Format.power(milliwatts: reading.milliwatts)) \(direction)"
        }
        return "No power readings yet"
    }

    private func chargerPortTitle(_ snapshot: HostSnapshot) -> String? {
        guard let key = snapshot.power.charger?.portKey else { return nil }
        return snapshot.port(key)?.label.title
    }
}

// MARK: - Totals

/// Four headline figures: system input, system load, port output, USB allocated.
struct PowerTotalsRow: View {
    var power: PowerSummary

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
            PowerStatTile(
                title: "System input",
                value: power.systemInputMilliwatts.map { Format.power(milliwatts: $0) } ?? "—",
                caption: "From the charger",
                systemName: "arrow.down.to.line",
                color: Lagoon.powerIn
            )
            PowerStatTile(
                title: "System load",
                value: power.systemLoadMilliwatts.map { Format.power(milliwatts: $0) } ?? "—",
                caption: "Used by the Mac",
                systemName: "cpu",
                color: Lagoon.accent
            )
            PowerStatTile(
                title: "Port output",
                value: Format.power(milliwatts: power.portOutputMilliwatts),
                caption: "Delivered to accessories",
                systemName: "arrow.up.right",
                color: Lagoon.accent
            )
            PowerStatTile(
                title: "USB allocated",
                value: Format.power(milliwatts: power.usbAllocatedMilliwatts),
                caption: "Budget granted to USB devices",
                systemName: "cable.connector",
                color: Lagoon.accent
            )
        }
    }
}

/// One headline number on a card.
struct PowerStatTile: View {
    var title: String
    var value: String
    var caption: String
    var systemName: String
    var color: Color
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemName).foregroundStyle(color)
            }
            .lagoonFont(.caption, weight: .semibold)
            .foregroundStyle(Lagoon.textSecondary)
            Text(value)
                .lagoonFont(size: 26, weight: .semibold, design: .rounded, monospacedDigits: true)
                .foregroundStyle(Lagoon.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .lagoonFont(.caption)
                .foregroundStyle(WindowContrast.tertiary(contrast))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lagoonCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Charger and battery

/// The charger: identity, contract and every power profile it offers.
struct PowerChargerCard: View {
    var power: PowerSummary
    var portTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Charger", trailing: portTitle)
            if let charger = power.charger {
                HStack(spacing: 12) {
                    Image(systemName: charger.isWireless ? "bolt.circle" : "powerplug.fill")
                        .lagoonFont(size: 18, weight: .semibold)
                        .foregroundStyle(Lagoon.powerIn)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Lagoon.powerIn.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(charger.displayName)
                            .lagoonFont(.headline, weight: .semibold)
                            .foregroundStyle(Lagoon.textPrimary)
                        Text(chargerSubtitle(charger))
                            .lagoonFont(.caption, monospacedDigits: true)
                            .foregroundStyle(Lagoon.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if let contract = charger.contractMilliwatts, contract > 0 {
                        PowerBadge(milliwatts: contract, direction: .input, isMeasured: false)
                    }
                }
                if charger.profiles.isEmpty {
                    Text("The charger did not list its power profiles.")
                        .lagoonFont(.callout)
                        .foregroundStyle(Lagoon.textSecondary)
                } else {
                    Rectangle().fill(Lagoon.stroke).frame(height: 1)
                    PowerProfilesGrid(profiles: charger.profiles)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: power.hasBattery ? "battery.75percent" : "powerplug")
                        .lagoonFont(size: 18, weight: .medium)
                        .foregroundStyle(Lagoon.textTertiary)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No charger connected")
                            .lagoonFont(.headline, weight: .semibold)
                            .foregroundStyle(Lagoon.textPrimary)
                        Text(power.hasBattery
                             ? "The Mac is running on its battery."
                             : "This Mac runs from mains power, so there is no charger to report.")
                            .lagoonFont(.callout)
                            .foregroundStyle(Lagoon.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lagoonCard(padding: 16)
    }

    private func chargerSubtitle(_ charger: ChargerInfo) -> String {
        var parts: [String] = []
        if let manufacturer = charger.manufacturer, !manufacturer.isEmpty { parts.append(manufacturer) }
        if let watts = charger.ratedWatts { parts.append("\(watts) W rated") }
        if let millivolts = charger.millivolts, let milliamps = charger.milliamps {
            parts.append(Format.contract(millivolts: millivolts, milliamps: milliamps))
        } else if let active = charger.activeProfile {
            parts.append(active.label)
        }
        if let family = charger.familyDescription { parts.append(family) }
        return parts.isEmpty ? "Power adapter" : parts.joined(separator: " · ")
    }
}

/// The internal battery: charge level, state and power.
struct PowerBatteryCard: View {
    var battery: BatteryInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Battery")
            if let battery {
                HStack(alignment: .firstTextBaseline) {
                    Text(battery.percent.map { "\($0)%" } ?? "—")
                        .lagoonFont(size: 30, weight: .semibold, design: .rounded, monospacedDigits: true)
                        .foregroundStyle(Lagoon.textPrimary)
                    Text(battery.statusText)
                        .lagoonFont(.callout)
                        .foregroundStyle(Lagoon.textSecondary)
                    Spacer(minLength: 0)
                }
                PowerBatteryBar(fraction: Double(battery.percent ?? 0) / 100, isCharging: battery.isCharging)
                    .frame(height: 8)
                if let milliwatts = battery.powerMilliwatts, milliwatts != 0 {
                    InspectorRow(
                        label: milliwatts > 0 ? "Charging at" : "Draining at",
                        value: Format.power(milliwatts: abs(milliwatts))
                    )
                }
                if let reason = battery.notChargingReason, reason != 0, battery.externalConnected {
                    InspectorRow(label: "Not charging reason", value: "Code \(reason)")
                }
            } else {
                Text("No battery reading yet.")
                    .lagoonFont(.callout)
                    .foregroundStyle(Lagoon.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lagoonCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}

/// A slim charge-level bar.
struct PowerBatteryBar: View {
    var fraction: Double
    var isCharging: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Lagoon.surfaceRaised)
                Capsule()
                    .fill(isCharging ? Lagoon.powerIn : Lagoon.accent)
                    .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .overlay(Capsule().strokeBorder(Lagoon.stroke, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: - Charts

/// System input, battery and system load over the last few minutes.
struct SystemPowerChartCard: View {
    var history: PowerHistory
    /// System load in watts (from `SystemLoadRecorder`).
    var load: [(date: Date, watts: Double)]

    var body: some View {
        let points = PowerChartData.systemPoints(history, load: load)
        let domain = [PowerChartData.inputName, PowerChartData.batteryName, PowerChartData.loadName]
            .filter { name in points.contains { $0.series == name } }
        let colors = domain.map(PowerChartData.systemColor)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "System power", trailing: "Last \(Int(history.window / 60)) minutes")
            if points.count < 2 {
                PowerChartEmpty(message: "System input, battery and system load appear here once a few readings arrive. Some Macs do not report them.")
            } else {
                PowerLineChart(
                    points: points,
                    domain: domain,
                    colors: colors,
                    areaSeries: PowerChartData.inputName,
                    showsZeroLine: points.contains { $0.watts < 0 }
                )
                .frame(height: 220)
            }
        }
        .lagoonCard(padding: 16)
    }
}

/// Power through each port over the last few minutes.
struct PortPowerChartCard: View {
    var history: PowerHistory
    var title: (PortKey) -> String

    var body: some View {
        let series = PowerChartData.portSeries(history, title: title)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Per-port power", trailing: "Positive: out to devices · negative: into the Mac")
            if series.points.count < 2 {
                PowerChartEmpty(message: "No port reports live power yet. Ports with a charger or a powered device show up here.")
            } else {
                PowerLineChart(
                    points: series.points,
                    domain: series.domain,
                    colors: series.colors,
                    areaSeries: nil,
                    showsZeroLine: true
                )
                .frame(height: 220)
            }
        }
        .lagoonCard(padding: 16)
    }
}

/// Placeholder inside a chart card when there is nothing to plot.
struct PowerChartEmpty: View {
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .lagoonFont(size: 26, weight: .light)
                .foregroundStyle(Lagoon.accent.opacity(0.6))
            Text(message)
                .lagoonFont(.callout)
                .foregroundStyle(Lagoon.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}
