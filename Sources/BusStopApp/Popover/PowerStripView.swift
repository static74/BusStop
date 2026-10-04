import BusStopCore
import SwiftUI

/// The power card under the header (docs/SPEC.md §3.2, item 2).
///
/// - With a charger: charger name, rated watts, active contract, a sparkline
///   of system input power, battery state and a power-in badge.
/// - On a laptop without a charger: battery state and how fast it drains.
/// - On a desktop: how much the accessories draw from the ports.
struct PowerStripView: View {
    var store: PortStore

    /// Number of history samples in the sparkline.
    static let sparklinePoints = 60

    var body: some View {
        let snapshot = store.snapshot
        let power = snapshot.power
        Group {
            if let charger = power.charger {
                chargerCard(charger, power: power)
            } else if power.hasBattery || snapshot.machine.isLaptop {
                batteryCard(power)
            } else {
                desktopCard(power)
            }
        }
        .lagoonCard()
    }

    // MARK: Charger

    private func chargerCard(_ charger: ChargerInfo, power: PowerSummary) -> some View {
        let measuredInput = power.systemInputMilliwatts.flatMap { $0 > 0 ? $0 : nil }
        let inputMilliwatts = measuredInput ?? charger.contractMilliwatts
        let series = store.history.systemInputSeries.suffix(Self.sparklinePoints).map { $0.watts }

        return HStack(alignment: .center, spacing: 12) {
            PowerTile(systemName: "bolt.fill", color: Lagoon.powerIn)
            VStack(alignment: .leading, spacing: 3) {
                Text(charger.displayName)
                    .font(Lagoon.titleFont)
                    .foregroundStyle(Lagoon.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let ratings = Self.ratingText(charger) {
                    Text(ratings)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Lagoon.textSecondary)
                        .lineLimit(1)
                }
                if let battery = power.battery {
                    BatteryStatusLabel(battery: battery)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                if let inputMilliwatts, inputMilliwatts > 0 {
                    PowerBadge(milliwatts: inputMilliwatts, direction: .input, isMeasured: measuredInput != nil)
                }
                if series.count >= 2 {
                    Sparkline(values: series, color: Lagoon.powerIn)
                        .frame(width: 84, height: 24)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.chargerAccessibilityLabel(charger, power: power, input: inputMilliwatts))
    }

    /// "96 W · 20 V × 4.7 A".
    static func ratingText(_ charger: ChargerInfo) -> String? {
        var parts: [String] = []
        if let watts = charger.ratedWatts, watts > 0 { parts.append("\(watts) W") }
        if let millivolts = charger.millivolts, let milliamps = charger.milliamps, millivolts > 0, milliamps > 0 {
            parts.append(Format.contract(millivolts: millivolts, milliamps: milliamps))
        } else if let profile = charger.activeProfile {
            parts.append(profile.label)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private static func chargerAccessibilityLabel(_ charger: ChargerInfo, power: PowerSummary, input: Int?) -> String {
        var parts = ["Charger: \(charger.displayName)"]
        if let ratings = ratingText(charger) { parts.append(ratings) }
        if let input, input > 0 { parts.append(PopoverText.spokenPower(milliwatts: input) + " in") }
        if let battery = power.battery { parts.append(battery.statusText) }
        return parts.joined(separator: ", ")
    }

    // MARK: Battery

    private func batteryCard(_ power: PowerSummary) -> some View {
        let battery = power.battery
        let accessories = Self.accessoryDraw(power)
        let drain = battery?.powerMilliwatts.flatMap { $0 < 0 ? -$0 : nil } ?? power.systemLoadMilliwatts

        return HStack(alignment: .center, spacing: 12) {
            PowerTile(systemName: battery.map(BatteryStatusLabel.symbolName(for:)) ?? "battery.75percent",
                      color: Lagoon.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(battery?.statusText ?? "On battery")
                    .font(Lagoon.titleFont)
                    .foregroundStyle(Lagoon.textPrimary)
                    .monospacedDigit()
                if let drain, drain > 0 {
                    Text("Using \(Format.power(milliwatts: drain))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Lagoon.textSecondary)
                }
                Text(accessories.milliwatts > 0
                     ? "Accessories draw \(Format.power(milliwatts: accessories.milliwatts))"
                     : "No charger connected")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Lagoon.textTertiary)
            }
            Spacer(minLength: 8)
            if accessories.milliwatts > 0 {
                PowerBadge(milliwatts: accessories.milliwatts, direction: .output, isMeasured: accessories.isMeasured)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Desktop

    private func desktopCard(_ power: PowerSummary) -> some View {
        let accessories = Self.accessoryDraw(power)
        let series = store.history.samples.suffix(Self.sparklinePoints).map { sample in
            Double(sample.portMilliwatts.values.filter { $0 > 0 }.reduce(0, +)) / 1000
        }
        let hasSeries = series.count >= 2 && series.contains { $0 > 0 }

        return HStack(alignment: .center, spacing: 12) {
            PowerTile(systemName: "powerplug.fill", color: Lagoon.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(accessories.milliwatts > 0
                     ? "Accessories draw \(Format.power(milliwatts: accessories.milliwatts))"
                     : "No accessory power draw")
                    .font(Lagoon.titleFont)
                    .foregroundStyle(Lagoon.textPrimary)
                    .monospacedDigit()
                Text(accessories.isMeasured ? "Measured at the ports" : "USB power allocated to devices")
                    .font(.caption)
                    .foregroundStyle(Lagoon.textSecondary)
            }
            Spacer(minLength: 8)
            if hasSeries {
                Sparkline(values: series)
                    .frame(width: 84, height: 24)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Power delivered to accessories: measured port output when known,
    /// otherwise the USB allocation budget.
    static func accessoryDraw(_ power: PowerSummary) -> (milliwatts: Int, isMeasured: Bool) {
        if power.portOutputMilliwatts > 0 { return (power.portOutputMilliwatts, true) }
        return (power.usbAllocatedMilliwatts, false)
    }
}

/// Square icon tile used in the power card.
private struct PowerTile: View {
    var systemName: String
    var color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(color.opacity(0.3), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// "Charging · 82%" with a battery symbol.
struct BatteryStatusLabel: View {
    var battery: BatteryInfo

    var body: some View {
        Label {
            Text(battery.statusText).monospacedDigit()
        } icon: {
            Image(systemName: Self.symbolName(for: battery))
        }
        .font(.caption)
        .foregroundStyle(battery.isCharging ? Lagoon.powerIn : Lagoon.textSecondary)
        .labelStyle(.titleAndIcon)
    }

    static func symbolName(for battery: BatteryInfo) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.percent ?? 50 {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}
