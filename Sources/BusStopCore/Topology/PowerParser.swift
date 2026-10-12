import Foundation

/// Charger, battery and per-port power (SPEC §5.4 "Power").
enum PowerParser {
    /// System-level readings from `PowerTelemetryData`, in mW.
    struct Telemetry: Equatable {
        var systemInput: Int?
        var systemLoad: Int?
        var battery: Int?
    }

    static func telemetry(_ battery: PropertyBag?) -> Telemetry {
        let data = battery?.bag("PowerTelemetryData")
        let input = TopologyValues.signedMilliwatts(data?["SystemPowerIn"]).map { max(0, $0) }
        let load = TopologyValues.signedMilliwatts(data?["SystemLoad"]).map { max(0, $0) }
        let batteryPower = TopologyValues.signedMilliwatts(data?["BatteryPower"])
            ?? TopologyValues.signedMilliwatts(battery?.bag("BatteryData")?["BatteryPower"])
        return Telemetry(systemInput: input, systemLoad: load, battery: batteryPower)
    }

    // MARK: - Battery

    /// Whether the Mac has an internal battery: `BatteryInstalled` when the
    /// battery service publishes it, else the machine info.
    static func hasBattery(_ raw: RawSnapshot) -> Bool {
        raw.machine.hasBattery || raw.battery?.bool("BatteryInstalled") == true
    }

    /// Battery state, or nil on Macs without one.
    static func battery(_ raw: RawSnapshot, telemetry: Telemetry) -> BatteryInfo? {
        guard let b = raw.battery else { return nil }
        let installed = b.bool("BatteryInstalled") ?? raw.machine.hasBattery
        guard installed else { return nil }

        var percent: Int?
        if let current = b.double("CurrentCapacity"), let maximum = b.double("MaxCapacity"), maximum > 0,
           current.isFinite, maximum.isFinite {
            percent = TopologyValues.int(min(100, max(0, current * 100 / maximum)))
        }
        let chargerData = b.bag("ChargerData")
        return BatteryInfo(percent: percent,
                           isCharging: b.bool("IsCharging") ?? chargerData?.bool("IsCharging") ?? false,
                           isFullyCharged: b.bool("FullyCharged") ?? false,
                           externalConnected: b.bool("ExternalConnected") ?? false,
                           notChargingReason: b.int("NotChargingReason") ?? chargerData?.int("NotChargingReason"),
                           powerMilliwatts: telemetry.battery)
    }

    // MARK: - Charger

    /// Sanity limits for adapter values. Anything outside is treated as
    /// missing, which also keeps the contract arithmetic far from overflow.
    static let maxMillivolts = 100_000
    static let maxMilliamps = 100_000

    /// True when an adapter dictionary says something about a real adapter
    /// (a disconnected Mac can still publish `{FamilyCode = 0}`).
    static func hasAdapterData(_ bag: PropertyBag?) -> Bool {
        guard let bag, !bag.isEmpty else { return false }
        if let watts = bag.int("Watts"), watts > 0 { return true }
        if TopologyText.clean(bag.string("Name")) != nil { return true }
        if let current = bag.int("Current"), current > 0 { return true }
        if let voltage = bag.int("AdapterVoltage"), voltage > 0 { return true }
        if let family = bag.int64("FamilyCode"), family != 0 { return true }
        if let menu = bag.bags("UsbHvcMenu"), !menu.isEmpty { return true }
        return false
    }

    /// "USB-C PD" and friends for the `FamilyCode` values in `IOPM.h`
    /// (`kIOPSFamilyCode…`), which arrive as signed 32-bit numbers.
    static func familyDescription(_ code: Int64?) -> String? {
        guard let code, code != 0 else { return nil }
        switch UInt32(truncatingIfNeeded: code) {
        case 0xE000_400A: return "USB-C PD"
        case 0xE000_4009: return "USB-C"
        case 0xE000_4008: return "USB-C"
        case 0xE000_4003: return "USB adapter"
        case 0xE000_4004, 0xE000_4005, 0xE000_4006: return "USB charging port"
        case 0xE000_4000, 0xE000_4001, 0xE000_4002, 0xE000_4007: return "USB"
        case 0xE001_0000: return "AC adapter"
        case 0xE001_0001...0xE001_0008: return "External power"
        default: return nil
        }
    }

    /// Offered profiles from `UsbHvcMenu` (`Index` with `MaxVoltage` /
    /// `MaxCurrent`, or `Voltage` / `Current`); the active one is
    /// `UsbHvcHvcIndex`.
    static func profiles(_ bag: PropertyBag?) -> [PowerProfile] {
        guard let bag, let menu = bag.bags("UsbHvcMenu") else { return [] }
        let active = bag.int("UsbHvcHvcIndex")
        var seen = Set<Int>()
        var result: [PowerProfile] = []
        for (offset, entry) in menu.enumerated() {
            let index = entry.int("Index") ?? offset
            guard let millivolts = entry.int(["MaxVoltage", "Voltage"]),
                  let milliamps = entry.int(["MaxCurrent", "Current"]),
                  (1...maxMillivolts).contains(millivolts), (0...maxMilliamps).contains(milliamps),
                  seen.insert(index).inserted else { continue }
            result.append(PowerProfile(index: index, millivolts: millivolts, maxMilliamps: milliamps,
                                       maxMilliwatts: entry.int(["MaxPower", "Power"]).flatMap { $0 > 0 ? $0 : nil },
                                       isActive: index == active))
        }
        return result.sorted { $0.index < $1.index }
    }

    /// The charger without its port, or nil when none is attached.
    ///
    /// `AdapterDetails` (battery service) is preferred over the IOPS adapter
    /// dictionary for each field. With `ExternalConnected = No`, only the
    /// IOPS dictionary (which is empty when nothing is attached) can produce
    /// a charger, so stale `AdapterDetails` never show a phantom adapter.
    static func charger(_ raw: RawSnapshot, portEvidence: Bool) -> ChargerInfo? {
        let details = raw.battery?.bag("AdapterDetails")
        let ioPS = raw.adapter
        let external = raw.battery?.bool("ExternalConnected")
        let detailsUsable = hasAdapterData(details) && external != false
        let ioPSUsable = hasAdapterData(ioPS)
        guard detailsUsable || ioPSUsable || (external == true && portEvidence) else { return nil }

        let sources = [detailsUsable ? details : nil, ioPSUsable ? ioPS : nil].compactMap { $0 }
        func string(_ key: String) -> String? { sources.lazy.compactMap { TopologyText.clean($0.string(key)) }.first }
        func positive(_ key: String, upTo limit: Int) -> Int? {
            sources.lazy.compactMap { $0.int(key) }.first { (1...limit).contains($0) }
        }

        let profileSource = sources.first { !(profiles($0).isEmpty) }
        let family = sources.lazy.compactMap { $0.int64("FamilyCode") }.first { $0 != 0 }
        return ChargerInfo(name: string("Name"), manufacturer: string("Manufacturer"),
                           ratedWatts: positive("Watts", upTo: 10_000),
                           millivolts: positive("AdapterVoltage", upTo: maxMillivolts),
                           milliamps: positive("Current", upTo: maxMilliamps),
                           profiles: profiles(profileSource),
                           isWireless: sources.lazy.compactMap { $0.bool("IsWireless") }.first ?? false,
                           familyDescription: familyDescription(family),
                           serialNumber: string("SerialNumber") ?? string("SerialString"))
    }

    // MARK: - Charger port

    /// Why a port was picked as the charging port, strongest first.
    enum ChargerPortEvidence: Int, Comparable {
        case powerSource = 0
        case magSafe = 1
        case powerIn = 2
        case appleCharger = 3

        static func < (lhs: ChargerPortEvidence, rhs: ChargerPortEvidence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The adapter's rated power in mW (`AdapterDetails` or the IOPS adapter
    /// `Watts`), for telling several charging ports apart.
    static func adapterMilliwatts(_ raw: RawSnapshot) -> Int? {
        let watts = [raw.battery?.bag("AdapterDetails"), raw.adapter].lazy.compactMap { $0?.int("Watts") }
            .first { (1...10_000).contains($0) }
        return watts.map { $0 * 1000 }
    }

    /// The port the Mac is charging through, most to least reliable
    /// evidence (only connected ports count):
    /// 1. a port whose `IOPortFeaturePowerSource` holds a winning option,
    ///    that is, a live power contract;
    /// 2. a connected MagSafe port (third-party MagSafe bricks never win a
    ///    PD contract);
    /// 3. a port with "Power In" in `FeaturesEnabled`;
    /// 4. a port where an Apple charger identified itself (`AppleUVDM`
    ///    "User String").
    ///
    /// Several ports can hold a winning option (a USB-C monitor that supplies
    /// power next to the charger, or a stale MagSafe contract). macOS then
    /// charges from the one with the most power: the port whose option is
    /// marked `[*]`, then whose `Max Power (mW)` matches the adapter's rated
    /// power (`adapterMilliwatts`, within 5 %), then the highest `Max Power`.
    /// If that still leaves a tie, the answer is nil, so the charger is shown
    /// without a port rather than on the wrong one.
    static func chargerPort(ports: TopologyPortTable, index: TopologyNodeIndex, connected: Set<PortKey>,
                            adapterMilliwatts: Int? = nil) -> (key: PortKey, evidence: ChargerPortEvidence)? {
        var candidates: [(PortKey, ChargerPortEvidence)] = []
        for record in ports.records where connected.contains(record.key) {
            if record.kind == .magSafe { candidates.append((record.key, .magSafe)) }
            if record.properties.strings("FeaturesEnabled")?.contains("Power In") == true {
                candidates.append((record.key, .powerIn))
            }
        }
        // Per port, the best winning option: (rank, Max Power).
        var contracts: [PortKey: (rank: Int, maxPower: Int?)] = [:]
        for node in index.nodes {
            let isPowerSource = TopologyClass.has(node, prefix: "IOPortFeaturePowerSource")
                || node.properties.has("WinningPowerSourceOption")
            if isPowerSource, TopologyValues.isEmpty(node.properties["WinningPowerSourceOption"]) == false,
               let key = ports.owner(of: node, index: index), connected.contains(key) {
                let name = node.properties.string("PowerSourceName") ?? node.name
                let rank = node.name.contains("[*]") ? 0 : (name.hasPrefix("USB-PD") ? 1 : name.hasPrefix("Brick") ? 2 : 3)
                let maxPower = node.properties.bag("WinningPowerSourceOption")?.int("Max Power (mW)")
                    .flatMap { $0 > 0 ? $0 : nil }
                if let current = contracts[key],
                   current.rank < rank || (current.rank == rank && (current.maxPower ?? 0) >= (maxPower ?? 0)) {
                    continue
                }
                contracts[key] = (rank, maxPower)
            }
            if TopologyClass.mentions(node, "AppleUVDM") || node.properties.string("ProtocolName") == "AppleUVDM",
               let text = node.properties.string("User String")?.lowercased(),
               text.contains("adapter") || text.contains("charger"),
               let key = ports.owner(of: node, index: index), connected.contains(key) {
                candidates.append((key, .appleCharger))
            }
        }
        if !contracts.isEmpty {
            return chargingContract(contracts, adapterMilliwatts: adapterMilliwatts).map { ($0, .powerSource) }
        }
        guard let best = candidates.min(by: { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
        }) else { return nil }
        return (best.0, best.1)
    }

    /// The port among several holding a winning option that the Mac charges
    /// from, or nil when that cannot be told (see `chargerPort`).
    private static func chargingContract(_ contracts: [PortKey: (rank: Int, maxPower: Int?)],
                                         adapterMilliwatts: Int?) -> PortKey? {
        guard let bestRank = contracts.values.map({ $0.rank }).min() else { return nil }
        var pool = contracts.filter { $0.value.rank == bestRank }
        if pool.count == 1 { return pool.first?.key }
        if let adapter = adapterMilliwatts, adapter > 0 {
            let matching = pool.filter { entry in
                guard let power = entry.value.maxPower else { return false }
                return abs(power - adapter) * 100 <= adapter * 5
            }
            if !matching.isEmpty { pool = matching }
            if pool.count == 1 { return pool.first?.key }
        }
        let powers = pool.compactMap { $0.value.maxPower }
        guard let most = powers.max(), powers.filter({ $0 == most }).count == 1 else { return nil }
        return pool.first { $0.value.maxPower == most }?.key
    }

    /// Fills charger fields the adapter dictionaries left empty from the
    /// charger port: the Apple charger's own name, the winning power-source
    /// contract. The winning source (`[*]` in its name) is read first, then
    /// nodes by registry ID, so the result does not depend on capture order.
    static func enrich(_ charger: inout ChargerInfo, port: PortKey, ports: TopologyPortTable,
                       index: TopologyNodeIndex) {
        let nodes = index.nodes.filter { ports.owner(of: $0, index: index) == port }.sorted { lhs, rhs in
            let l = lhs.name.contains("[*]") ? 0 : 1
            let r = rhs.name.contains("[*]") ? 0 : 1
            return l != r ? l < r : lhs.id < rhs.id
        }
        for node in nodes {
            let p = node.properties
            if TopologyClass.mentions(node, "AppleUVDM") || p.string("ProtocolName") == "AppleUVDM" {
                if charger.name == nil { charger.name = TopologyText.clean(p.string("User String")) }
                if charger.manufacturer == nil { charger.manufacturer = TopologyText.clean(p.string("Vendor")) }
                if charger.serialNumber == nil { charger.serialNumber = TopologyText.clean(p.string("Serial Number")) }
            }
            if let option = p.bag("WinningPowerSourceOption") {
                if charger.millivolts == nil {
                    charger.millivolts = option.int("Voltage (mV)").flatMap { (1...maxMillivolts).contains($0) ? $0 : nil }
                }
                if charger.milliamps == nil {
                    charger.milliamps = option.int("Max Current (mA)").flatMap { (1...maxMilliamps).contains($0) ? $0 : nil }
                }
            }
        }
        if charger.familyDescription == nil, ports.record(port)?.kind == .magSafe {
            charger.familyDescription = "MagSafe"
        }
    }

    // MARK: - Per-port power

    /// Lowercase hex without dashes or spaces, for UUID joins.
    static func normalizedUUID(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.lowercased().filter { $0.isHexDigit }
        return cleaned.isEmpty ? nil : cleaned
    }

    /// The SMC channel for each port, joined by HPM controller UUID. A UUID
    /// shared by several ports is ambiguous and joins nothing.
    ///
    /// Some Macs publish a blank `UUID` on one HPM controller while the SMC
    /// still lists its channel. That port is joined by elimination (after
    /// WhatPort's `PortManager.joinUnidentifiedPortByElimination`), only when
    /// everything lines up: exactly one USB-C port has no UUID, exactly one
    /// channel's UUID belongs to no port, there is one channel per USB-C and
    /// MagSafe port, and the spare channel's index is the port's rank among
    /// the USB-C ports (channels count from 1).
    static func smcChannels(_ raw: RawSnapshot, ports: TopologyPortTable) -> [PortKey: SMCChannel] {
        var uuidPorts: [String: [PortKey]] = [:]
        for record in ports.records {
            if let uuid = normalizedUUID(raw.portControllerUUIDs[record.key.description]) {
                uuidPorts[uuid, default: []].append(record.key)
            }
        }
        var result: [PortKey: SMCChannel] = [:]
        for channel in raw.smcChannels.sorted(by: { $0.index < $1.index }) {
            guard let uuid = normalizedUUID(channel.uuid), let keys = uuidPorts[uuid], keys.count == 1,
                  result[keys[0]] == nil else { continue }
            result[keys[0]] = channel
        }

        // Join by elimination.
        let usbC = ports.records.filter { $0.kind == .usbC || $0.kind == .thunderbolt }
            .sorted { ($0.number, $0.key) < ($1.number, $1.key) }
        let unidentified = usbC.filter { normalizedUUID(raw.portControllerUUIDs[$0.key.description]) == nil }
        let spare = raw.smcChannels.filter { channel in
            guard let uuid = normalizedUUID(channel.uuid) else { return false }
            return uuidPorts[uuid] == nil
        }
        let magSafeCount = ports.records.filter { $0.kind == .magSafe }.count
        guard unidentified.count == 1, spare.count == 1, raw.smcChannels.count == usbC.count + magSafeCount,
              let rank = usbC.firstIndex(where: { $0.key == unidentified[0].key }),
              spare[0].index == rank + 1, result[unidentified[0].key] == nil else { return result }
        result[unidentified[0].key] = spare[0]
        return result
    }

    /// A live SMC reading, or nil below 50 mW or when values are missing.
    static func smcPower(_ channel: SMCChannel, direction: PowerDirection) -> PortPower? {
        guard let volts = channel.volts, let amps = channel.amps, volts.isFinite, amps.isFinite,
              let milliwatts = TopologyValues.int(abs(volts * amps * 1000)), milliwatts >= 50 else { return nil }
        return PortPower(direction: direction, milliwatts: milliwatts,
                         millivolts: TopologyValues.int(abs(volts) * 1000),
                         milliamps: TopologyValues.int(abs(amps) * 1000), source: .smc)
    }

    /// `PowerOutDetails` entries by USB-C port number. `Watts` is in mW;
    /// `PortIndex` is the port number (offset + 1 when missing or zero).
    static func powerOutDetails(_ battery: PropertyBag?) -> [Int: PortPower] {
        guard let entries = battery?.bags("PowerOutDetails") else { return [:] }
        var result: [Int: PortPower] = [:]
        for (offset, entry) in entries.enumerated() {
            let index = entry.int("PortIndex").flatMap { $0 > 0 ? $0 : nil } ?? offset + 1
            guard let milliwatts = entry.int("Watts"), milliwatts > 0, milliwatts < 1_000_000,
                  result[index] == nil else { continue }
            let millivolts = entry.int(["AdapterVoltage", "ConfiguredVoltage"]).flatMap { $0 > 0 ? $0 : nil }
            let milliamps = entry.int(["Current", "ConfiguredCurrent"]).flatMap { $0 > 0 ? $0 : nil }
            result[index] = PortPower(direction: .output, milliwatts: milliwatts, millivolts: millivolts,
                                      milliamps: milliamps, source: .powerOutDetails)
        }
        return result
    }

    /// Power through one port, best source first: SMC, `PowerOutDetails`
    /// (USB-C only, never the charger port), telemetry or contract for the
    /// charger port, then the sum of USB allocations.
    ///
    /// `PowerOutDetails` can freeze at its last value after a device is
    /// unplugged, so it counts only on a connected port, and not when the
    /// port's SMC channel is live and reads (almost) nothing.
    static func portPower(for port: PhysicalPort, isChargerPort: Bool, charger: ChargerInfo?,
                          smc: SMCChannel?, powerOut: [Int: PortPower], telemetry: Telemetry) -> PortPower? {
        let direction: PowerDirection = isChargerPort ? .input : .output
        if let smc, let reading = smcPower(smc, direction: direction) { return reading }
        let smcReadsNothing = smc.map { $0.volts?.isFinite == true && $0.amps?.isFinite == true } ?? false
        if !isChargerPort, port.isConnected, !smcReadsNothing, port.kind == .usbC || port.kind == .thunderbolt,
           let reading = powerOut[port.number] {
            return reading
        }
        if isChargerPort {
            if let input = telemetry.systemInput, input > 0 {
                return PortPower(direction: .input, milliwatts: input, source: .telemetry)
            }
            if let contract = charger?.contractMilliwatts, contract > 0 {
                return PortPower(direction: .input, milliwatts: contract, millivolts: charger?.millivolts,
                                 milliamps: charger?.milliamps, source: .pdContract)
            }
            return nil
        }
        let allocated = hostAllocatedMilliwatts(port)
        return allocated > 0 ? PortPower(direction: .output, milliwatts: allocated, source: .usbAllocation) : nil
    }

    /// USB power the Mac itself supplies through a port
    /// (`PhysicalPort.hostAllocatedMilliwatts`). The Mac's own draw toward a
    /// dock or display shows up in the SMC instead.
    static func hostAllocatedMilliwatts(_ port: PhysicalPort) -> Int {
        port.hostAllocatedMilliwatts
    }
}
