import BusStopCore
import BusStopUI
import SwiftUI

/// The Power page: where the power goes, the charger and its profiles, the battery, and
/// power over time for the system and for each port, over the last 10
/// minutes (live) or the last hour, day or week (saved history).
struct PowerDetailView: View {
    var store: PortStore
    @State private var range = PowerRange.tenMinutes
    @State private var cache = SavedPowerCache()

    var body: some View {
        let snapshot = store.snapshot
        let power = snapshot.power
        let samples = samples(for: range, snapshot: snapshot)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(subtitle(power))

                PowerFlowCard(power: power, ports: snapshot.ports)

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

                SystemPowerChartCard(samples: samples, range: range,
                                     spanText: spanText(samples, snapshot: snapshot))
                PortPowerChartCard(samples: samples, range: range) { key in
                    snapshot.port(key)?.label.title ?? "Port \(key)"
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The range picker beside the title, or under it when one row does not
    /// fit beside the inspector.
    private func header(_ subtitle: String) -> some View {
        ViewThatFits(in: .horizontal) {
            WindowDetailHeader(title: "Power", subtitle: subtitle) { rangePicker }
            VStack(alignment: .leading, spacing: 10) {
                WindowDetailHeader(title: "Power", subtitle: subtitle)
                rangePicker
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var rangePicker: some View {
        Picker("Chart range", selection: $range) {
            ForEach(PowerRange.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("How far back the power charts reach. Ten minutes is live; longer ranges come from saved history.")
    }

    /// The live buffer for ten minutes, else the saved minutes for this Mac
    /// model, resampled once per new saved minute rather than on every capture.
    private func samples(for range: PowerRange, snapshot: HostSnapshot) -> [PowerSample] {
        guard range != .tenMinutes else { return store.history.samples }
        let model = snapshot.machine.model
        let saved = store.archive.sections[model]?.power ?? []
        let key = SavedPowerCache.Key(range: range, model: model, newest: saved.last?.start, count: saved.count)
        if cache.key != key {
            cache.key = key
            cache.samples = store.archive.powerSamples(model: model, since: snapshot.capturedAt - range.span,
                                                       step: range.step)
        }
        return cache.samples
    }

    /// The range, and when the samples start if that is later than the range
    /// would reach (history saved for a shorter time, or a fresh launch).
    private func spanText(_ samples: [PowerSample], snapshot: HostSnapshot) -> String {
        guard let first = samples.first?.date,
              first > snapshot.capturedAt - range.span + range.maxGap else { return range.spanText }
        return range.spanText + " · since " + first.formatted(range.tooltipFormat)
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

// MARK: - Flow

/// Where the power goes: what comes in, how it splits between the Mac and
/// its battery (in the System power chart's colours), and what the ports
/// hand to accessories, measured or only budgeted.
struct PowerFlowCard: View {
    var power: PowerSummary
    var ports: [PhysicalPort]
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let input = power.systemInputMilliwatts ?? 0
        let load = power.systemLoadMilliwatts
        let charging = max(0, power.battery?.powerMilliwatts ?? 0)
        VStack(alignment: .leading, spacing: 10) {
            // With a charger the page subtitle already gives the input.
            if input <= 0 {
                Text(headline(load: load))
                    .lagoonFont(.title3, weight: .semibold)
                    .foregroundStyle(Lagoon.textPrimary)
            }
            if input > 0, let load {
                // ponytail: losses and readings taken a moment apart can leave
                // a gap; it stays an unlabelled track rather than a guess.
                let total = CGFloat(max(input, load + charging))
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        segment(PowerChartPalette.systemLoad, CGFloat(load) / total * proxy.size.width)
                        if charging > 0 {
                            segment(PowerChartPalette.battery, CGFloat(charging) / total * proxy.size.width)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(Lagoon.surfaceRaised))
                    .clipShape(Capsule())
                }
                .frame(height: 10)
                HStack(spacing: 16) {
                    key(PowerChartPalette.systemLoad, "\(Format.power(milliwatts: load)) used by the Mac")
                    if charging > 0 {
                        key(PowerChartPalette.battery, "\(Format.power(milliwatts: charging)) into the battery")
                    }
                }
            }
            if let accessories = accessoriesText {
                Text(accessories)
                    .lagoonFont(.callout)
                    .foregroundStyle(WindowContrast.tertiary(contrast))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lagoonCard(padding: 16)
        .accessibilityElement(children: .combine)
    }

    /// "9.4 W from the battery", or the load alone on a Mac without one.
    private func headline(load: Int?) -> String {
        guard let load else { return "No power readings yet" }
        let source = power.hasBattery ? "from the battery" : "used by the Mac"
        return "\(Format.power(milliwatts: load)) \(source)"
    }

    /// Port output to accessories, named for what it is: measured at the
    /// port, or only the USB budget the Mac granted.
    private var accessoriesText: String? {
        let outputs = ports.compactMap { $0.power?.direction == .output ? $0.power : nil }
        let measured = outputs.filter(\.isMeasured).reduce(0) { $0 + ($1.milliwatts ?? 0) }
        let budgeted = outputs.filter { !$0.isMeasured }.reduce(0) { $0 + ($1.milliwatts ?? 0) }
        var parts: [String] = []
        if measured > 0 { parts.append("\(Format.power(milliwatts: measured)) measured") }
        if budgeted > 0 { parts.append("up to \(Format.power(milliwatts: budgeted)) budgeted") }
        guard !parts.isEmpty else { return nil }
        return "Accessories: " + parts.joined(separator: ", plus ") + "."
    }

    private func segment(_ color: Color, _ width: CGFloat) -> some View {
        Rectangle().fill(color).frame(width: max(0, width))
    }

    private func key(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .lagoonFont(.callout, monospacedDigits: true)
                .foregroundStyle(Lagoon.textSecondary)
        }
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
        // The contract only when the profile table below cannot mark it.
        if charger.profiles.isEmpty, let millivolts = charger.millivolts, let milliamps = charger.milliamps {
            parts.append(Format.contract(millivolts: millivolts, milliamps: milliamps))
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
                    Text(battery.stateText)
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

/// Saved power resampled for one range. A reference type, so `body` can
/// refresh it without invalidating the view.
final class SavedPowerCache {
    struct Key: Equatable {
        var range: PowerRange
        var model: String
        var newest: Date?
        var count: Int
    }

    var key: Key?
    var samples: [PowerSample] = []
}

/// System input, battery and system load over the chosen range.
struct SystemPowerChartCard: View {
    var samples: [PowerSample]
    var range: PowerRange
    var spanText: String

    var body: some View {
        let points = PowerChartData.systemPoints(samples, maxGap: range.maxGap)
        let domain = [PowerChartData.inputName, PowerChartData.batteryName, PowerChartData.loadName]
            .filter { name in points.contains { $0.series == name } }
        let colors = domain.map(PowerChartData.systemColor)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "System power", trailing: spanText)
            if points.isEmpty {
                PowerChartEmpty(message: "System input, battery and system load appear here once readings arrive. Some Macs do not report them.")
            } else {
                PowerLineChart(
                    points: points,
                    isolatedPoints: PowerChartData.isolated(points),
                    domain: domain,
                    colors: colors,
                    areaSeries: PowerChartData.inputName,
                    showsZeroLine: points.contains { $0.watts < 0 },
                    range: range
                )
                .frame(height: 220)
            }
        }
        .lagoonCard(padding: 16)
    }
}

/// Power through each port over the chosen range.
struct PortPowerChartCard: View {
    var samples: [PowerSample]
    var range: PowerRange
    var title: (PortKey) -> String

    var body: some View {
        let series = PowerChartData.portSeries(samples, title: title, maxGap: range.maxGap)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Per-port power", trailing: "Positive: out to devices · negative: into the Mac")
            if series.points.isEmpty {
                PowerChartEmpty(message: "No port reports live power yet. Ports with a charger or a powered device show up here.")
            } else {
                PowerLineChart(
                    points: series.points,
                    isolatedPoints: PowerChartData.isolated(series.points),
                    domain: series.domain,
                    colors: series.colors,
                    areaSeries: nil,
                    showsZeroLine: true,
                    range: range
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
