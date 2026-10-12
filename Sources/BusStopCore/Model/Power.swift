import Foundation

/// One USB-PD power profile (PDO) offered by a charger.
public struct PowerProfile: Sendable, Hashable, Codable, Identifiable {
    public var index: Int
    public var millivolts: Int
    public var maxMilliamps: Int
    /// The charger's stated maximum for this profile, or volts × amps.
    public var maxMilliwatts: Int
    /// The profile currently in use.
    public var isActive: Bool

    public var id: Int { index }

    public init(index: Int, millivolts: Int, maxMilliamps: Int, maxMilliwatts: Int? = nil, isActive: Bool = false) {
        self.index = index
        self.millivolts = millivolts
        self.maxMilliamps = maxMilliamps
        self.maxMilliwatts = maxMilliwatts ?? (millivolts * maxMilliamps / 1000)
        self.isActive = isActive
    }

    /// "20 V × 4.7 A"
    public var label: String {
        "\(Format.voltage(millivolts: millivolts)) × \(Format.current(milliamps: maxMilliamps))"
    }
}

/// The power adapter the Mac is charging from.
public struct ChargerInfo: Sendable, Hashable, Codable {
    /// "96W USB-C Power Adapter"
    public var name: String?
    public var manufacturer: String?
    /// Rated watts (`Watts`).
    public var ratedWatts: Int?
    /// Active contract voltage (`AdapterVoltage`, mV).
    public var millivolts: Int?
    /// Active contract current (`Current`, mA).
    public var milliamps: Int?
    /// Offered profiles (`UsbHvcMenu`), with the active one marked.
    public var profiles: [PowerProfile]
    public var isWireless: Bool
    /// The port the charger is plugged into, when known.
    public var portKey: PortKey?
    /// "USB-C PD", "MagSafe", "Apple", …
    public var familyDescription: String?
    public var serialNumber: String?

    public init(name: String? = nil, manufacturer: String? = nil, ratedWatts: Int? = nil, millivolts: Int? = nil,
                milliamps: Int? = nil, profiles: [PowerProfile] = [], isWireless: Bool = false, portKey: PortKey? = nil,
                familyDescription: String? = nil, serialNumber: String? = nil) {
        self.name = name
        self.manufacturer = manufacturer
        self.ratedWatts = ratedWatts
        self.millivolts = millivolts
        self.milliamps = milliamps
        self.profiles = profiles
        self.isWireless = isWireless
        self.portKey = portKey
        self.familyDescription = familyDescription
        self.serialNumber = serialNumber
    }

    /// The active profile, if one is marked.
    public var activeProfile: PowerProfile? { profiles.first(where: \.isActive) }

    /// Contract power: volts × amps of the active contract, in mW.
    public var contractMilliwatts: Int? {
        guard let millivolts, let milliamps else { return activeProfile?.maxMilliwatts }
        return millivolts * milliamps / 1000
    }

    /// "96 W" or the name when the wattage is unknown.
    public var displayName: String {
        name ?? ratedWatts.map { "\($0)W Power Adapter" } ?? "Power adapter"
    }
}

/// Internal battery state (laptops).
public struct BatteryInfo: Sendable, Hashable, Codable {
    /// 0–100.
    public var percent: Int?
    public var isCharging: Bool
    public var isFullyCharged: Bool
    public var externalConnected: Bool
    /// `NotChargingReason`; 0 or nil means none.
    public var notChargingReason: Int?
    /// Power into (+) or out of (−) the battery, mW (`BatteryPower`).
    public var powerMilliwatts: Int?

    public init(percent: Int? = nil, isCharging: Bool = false, isFullyCharged: Bool = false,
                externalConnected: Bool = false, notChargingReason: Int? = nil, powerMilliwatts: Int? = nil) {
        self.percent = percent
        self.isCharging = isCharging
        self.isFullyCharged = isFullyCharged
        self.externalConnected = externalConnected
        self.notChargingReason = notChargingReason
        self.powerMilliwatts = powerMilliwatts
    }

    /// "Charging · 82%", "Charged", "On battery · 64%", "Not charging · 80%".
    public var statusText: String {
        let pct = percent.map { " · \($0)%" } ?? ""
        if isFullyCharged && externalConnected { return "Charged" + pct }
        if isCharging { return "Charging" + pct }
        if externalConnected { return "Not charging" + pct }
        return "On battery" + pct
    }
}

/// Host-level power roll-up.
public struct PowerSummary: Sendable, Hashable, Codable {
    public var charger: ChargerInfo?
    public var battery: BatteryInfo?
    /// Power entering the Mac from the adapter, mW (`SystemPowerIn`).
    public var systemInputMilliwatts: Int?
    /// Power the Mac itself is consuming, mW (`SystemLoad`).
    public var systemLoadMilliwatts: Int?
    /// Sum of measured or estimated power delivered out of the ports, mW.
    public var portOutputMilliwatts: Int
    /// Sum of USB power allocations drawn from the Mac's own ports, mW.
    /// Devices behind a Thunderbolt dock or a self-powered hub are left out,
    /// because their power comes from that dock or hub.
    public var usbAllocatedMilliwatts: Int
    public var hasBattery: Bool

    public init(charger: ChargerInfo? = nil, battery: BatteryInfo? = nil, systemInputMilliwatts: Int? = nil,
                systemLoadMilliwatts: Int? = nil, portOutputMilliwatts: Int = 0, usbAllocatedMilliwatts: Int = 0,
                hasBattery: Bool = false) {
        self.charger = charger
        self.battery = battery
        self.systemInputMilliwatts = systemInputMilliwatts
        self.systemLoadMilliwatts = systemLoadMilliwatts
        self.portOutputMilliwatts = portOutputMilliwatts
        self.usbAllocatedMilliwatts = usbAllocatedMilliwatts
        self.hasBattery = hasBattery
    }

    /// The headline figure for the menu bar: power in when charging,
    /// otherwise power delivered to accessories.
    public var headlineMilliwatts: Int? {
        if let systemInputMilliwatts, systemInputMilliwatts > 0 { return systemInputMilliwatts }
        if let contract = charger?.contractMilliwatts, contract > 0 { return contract }
        let out = max(portOutputMilliwatts, usbAllocatedMilliwatts)
        return out > 0 ? out : nil
    }
}
