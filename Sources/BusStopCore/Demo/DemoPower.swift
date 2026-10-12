import Foundation

/// An Apple USB-C power adapter as the battery service and the power-source
/// API describe it.
struct DemoAdapter {
    var name: String
    var watts: Int
    /// `Model`, e.g. `"0x7012"`.
    var model: String
    var serial: String
    /// Offered fixed profiles (PDOs), lowest voltage first: (mV, mA).
    var profiles: [(millivolts: Int, milliamps: Int)]
    /// Index into `profiles` of the contract in use (`UsbHvcHvcIndex`).
    var activeIndex: Int

    var active: (millivolts: Int, milliamps: Int) {
        profiles.indices.contains(activeIndex) ? profiles[activeIndex] : (millivolts: 5_000, milliamps: 3_000)
    }

    /// `kIOPSFamilyCodeUSBCPD` as the registry stores it (signed 32-bit).
    static let usbCPDFamilyCode: Int64 = -536_854_518

    /// Apple 140W USB-C Power Adapter (USB PD 3.1 EPR, 28 V × 5 A).
    static let apple140W = DemoAdapter(
        name: "140W USB-C Power Adapter", watts: 140, model: "0x7016", serial: "C4H3271027Q1F4MAN",
        profiles: [(5_000, 3_000), (9_000, 3_000), (15_000, 3_000), (20_000, 4_700), (28_000, 5_000)],
        activeIndex: 4)

    /// Apple 70W USB-C Power Adapter (20 V × 3.5 A).
    static let apple70W = DemoAdapter(
        name: "70W USB-C Power Adapter", watts: 70, model: "0x7019", serial: "C4H3504001J1LXGAH",
        profiles: [(5_000, 3_000), (9_000, 3_000), (15_000, 3_000), (20_000, 3_500)],
        activeIndex: 3)

    /// `AppleSmartBattery.AdapterDetails` (menu keys `MaxVoltage` / `MaxCurrent`).
    var adapterDetails: PlistValue {
        .dict([
            "Name": .string(name),
            "Manufacturer": "Apple Inc.",
            "Model": .string(model),
            "Description": "pd charger",
            "SerialString": .string(serial),
            "Watts": .int(Int64(watts)),
            "AdapterVoltage": .int(Int64(active.millivolts)),
            "Current": .int(Int64(active.milliamps)),
            "PMUConfiguration": .int(Int64(active.milliamps)),
            "FamilyCode": .int(Self.usbCPDFamilyCode),
            "AdapterID": 28_675,
            "AdapterPowerTier": .int(watts >= 100 ? 4 : 3),
            "IsWireless": 0,
            "FwVersion": "01070052",
            "HwVersion": "1.0",
            "UsbHvcHvcIndex": .int(Int64(activeIndex)),
            "UsbHvcMenu": .array(profiles.enumerated().map { offset, profile in
                .dict(["Index": .int(Int64(offset)), "MaxVoltage": .int(Int64(profile.millivolts)),
                       "MaxCurrent": .int(Int64(profile.milliamps))])
            }),
        ])
    }

    /// `IOPSCopyExternalPowerAdapterDetails()` (menu keys `Voltage` / `Current`).
    var powerSourceDetails: PropertyBag {
        [
            "Name": .string(name),
            "Manufacturer": "Apple Inc.",
            "Model": .string(model),
            "Description": "pd charger",
            "SerialString": .string(serial),
            "Watts": .int(Int64(watts)),
            "AdapterVoltage": .int(Int64(active.millivolts)),
            "Current": .int(Int64(active.milliamps)),
            "FamilyCode": .int(Self.usbCPDFamilyCode),
            "AdapterID": 28_675,
            "IsWireless": false,
            "Source": "AC",
            "UsbHvcHvcIndex": .int(Int64(activeIndex)),
            "UsbHvcMenu": .array(profiles.enumerated().map { offset, profile in
                .dict(["Index": .int(Int64(offset)), "Voltage": .int(Int64(profile.millivolts)),
                       "Current": .int(Int64(profile.milliamps))])
            }),
        ]
    }

    /// The `USB-PD` power source options the port controller lists, lowest
    /// first, so the active contract is the last one.
    func powerSourceOptions(uuidSeed: UInt64) -> [PlistValue] {
        profiles.prefix(activeIndex + 1).enumerated().map { offset, profile in
            DemoRegistry.powerOption(millivolts: profile.millivolts, milliamps: profile.milliamps,
                                     uuid: DemoPower.uuid(seed: uuidSeed &+ UInt64(offset)))
        }
    }
}

/// Power flow of a laptop at one moment, in mW, as `PowerTelemetryData`
/// reports it. `systemLoad + batteryPower == systemPowerIn`.
struct DemoPowerFlow {
    var systemPowerIn: Int
    var systemVoltageIn: Int
    var systemLoad: Int

    var batteryPower: Int { systemPowerIn - systemLoad }

    var telemetry: PlistValue {
        let current = systemVoltageIn > 0 ? systemPowerIn * 1000 / systemVoltageIn : 0
        let loss = systemPowerIn * 23 / 1000
        return .dict([
            "SystemPowerIn": .int(Int64(systemPowerIn)),
            "SystemVoltageIn": .int(Int64(systemVoltageIn)),
            "SystemCurrentIn": .int(Int64(current)),
            "SystemLoad": .int(Int64(systemLoad)),
            "BatteryPower": .int(Int64(batteryPower)),
            "AdapterEfficiencyLoss": .int(Int64(loss)),
            "SystemEnergyConsumed": .int(Int64(systemLoad / 4)),
            "WallEnergyEstimate": .int(Int64((systemLoad + loss) / 4)),
            "SystemEffectiveTotalLoad": .int(Int64(systemLoad)),
            "PowerTelemetryErrorCount": 0,
        ])
    }
}

/// Battery-service records and helpers shared by the demo scenarios.
enum DemoPower {
    /// `AppleSmartBattery` of a laptop. `voltage` is the pack voltage in mV;
    /// `Amperage` follows from the battery power so the numbers agree.
    static func laptopBattery(percent: Int, charging: Bool, adapter: DemoAdapter?, flow: DemoPowerFlow,
                              voltage: Int, cycleCount: Int, minutesRemaining: Int,
                              powerOut: [PlistValue] = []) -> PropertyBag {
        let external = adapter != nil
        let amperage = voltage > 0 ? flow.batteryPower * 1000 / voltage : 0
        var p: [String: PlistValue] = [
            "BatteryInstalled": true,
            "ExternalConnected": .bool(external),
            "AppleRawExternalConnected": .bool(external),
            "ExternalChargeCapable": .bool(external),
            "IsCharging": .bool(charging),
            "FullyCharged": .bool(percent >= 100),
            "CurrentCapacity": .int(Int64(percent)),
            "MaxCapacity": 100,
            "CycleCount": .int(Int64(cycleCount)),
            "Voltage": .int(Int64(voltage)),
            "Amperage": .int(Int64(amperage)),
            "TimeRemaining": .int(Int64(minutesRemaining)),
            "AvgTimeToFull": .int(charging ? Int64(minutesRemaining) : 65_535),
            "AvgTimeToEmpty": .int(external ? 65_535 : Int64(minutesRemaining)),
            "BestAdapterIndex": .int(external ? 1 : 0),
            "ChargerData": .dict([
                "IsCharging": .int(charging ? 1 : 0),
                "NotChargingReason": 0,
                "SlowChargingReason": 0,
                "PMUConfiguration": .int(Int64(adapter?.active.milliamps ?? 0)),
            ]),
            "BatteryData": .dict([
                "CurrentCapacity": .int(Int64(percent)),
                "MaxCapacity": 100,
                "DesignCapacity": 6_249,
                "FullChargeCapacity": 6_031,
                "CycleCount": .int(Int64(cycleCount)),
                "BatteryPower": .int(Int64(flow.batteryPower)),
            ]),
            "PowerTelemetryData": flow.telemetry,
        ]
        p["AdapterDetails"] = adapter?.adapterDetails ?? .dict(["FamilyCode": 0])
        if !powerOut.isEmpty { p["PowerOutDetails"] = .array(powerOut) }
        return PropertyBag(p)
    }

    /// `AppleSmartBattery` on a desktop: the service exists, without a
    /// battery and without power telemetry.
    static func desktopBattery() -> PropertyBag {
        [
            "BatteryInstalled": false,
            "ExternalConnected": true,
            "AppleRawExternalConnected": true,
            "ExternalChargeCapable": false,
            "IsCharging": false,
            "CurrentCapacity": 0,
            "MaxCapacity": 0,
            "CycleCount": 0,
            "Voltage": 0,
            "Amperage": 0,
            "TimeRemaining": 0,
            "BestAdapterIndex": 0,
            "AdapterDetails": ["FamilyCode": 0],
        ]
    }

    /// One `PowerOutDetails` entry: `Watts` in mW for the USB-C port
    /// numbered `port` (`PortIndex`).
    static func powerOut(port: Int, milliwatts: Int, millivolts: Int, contractMilliamps: Int = 3_000) -> PlistValue {
        .dict([
            "PortIndex": .int(Int64(port)),
            "PortType": 2,
            "Watts": .int(Int64(milliwatts)),
            "Current": .int(Int64(millivolts > 0 ? milliwatts * 1000 / millivolts : 0)),
            "AdapterVoltage": .int(Int64(millivolts)),
            "ConfiguredVoltage": .int(Int64(millivolts)),
            "ConfiguredCurrent": .int(Int64(contractMilliamps)),
            "PDPowermW": .int(Int64(millivolts * contractMilliamps / 1000)),
        ])
    }

    /// An SMC power channel (`DxUI`, `DxJV`, `DxJI`, `DxPR`, `DxMP`). The
    /// UUID is the HPM controller's, without dashes, in lowercase.
    static func channel(_ index: Int, uuid: String, volts: Double, amps: Double,
                        contractMilliwatts: Int? = nil) -> SMCChannel {
        SMCChannel(index: index, uuid: uuid.replacingOccurrences(of: "-", with: "").lowercased(),
                   volts: volts, amps: amps, present: volts > 0, contractMilliwatts: contractMilliwatts)
    }

    /// A deterministic UUID-shaped string (`8-4-4-4-12`, uppercase), for HPM
    /// controller and power-option UUIDs.
    static func uuid(seed: UInt64) -> String {
        var state = seed
        func next() -> UInt64 {
            // SplitMix64.
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        let hex = Array(DemoRegistry.hexLocation(next(), width: 16) + DemoRegistry.hexLocation(next(), width: 16))
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
        return groups.map { String(hex[$0]) }.joined(separator: "-")
    }

    /// Milliwatts as a whole number.
    static func milliwatts(_ value: Double) -> Int {
        Int(value.rounded())
    }
}
