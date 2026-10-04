import Foundation
import Testing
@testable import BusStopCore

@Suite("Topology: power")
struct PowerTopologyTests {
    typealias F = TopologyFixtures

    static let adapter96: PropertyBag = [
        "Watts": 96, "AdapterVoltage": 20000, "Current": 4700, "Name": "96W USB-C Power Adapter",
        "Manufacturer": "Apple Inc.", "FamilyCode": .int(-536854518), "IsWireless": false,
        "UsbHvcHvcIndex": 2,
        "UsbHvcMenu": [["Index": 0, "Voltage": 5000, "Current": 3000],
                       ["Index": 1, "Voltage": 9000, "Current": 3000],
                       ["Index": 2, "Voltage": 20000, "Current": 4700]],
    ]

    // MARK: SMC

    @Test func smcChannelsJoinByControllerUUID() throws {
        let powerSource = F.node(
            id: 20, parent: 2, className: "IOPortFeaturePowerSource", name: "USB-PD [*]",
            properties: ["ParentPortType": 2, "ParentPortNumber": 2, "PowerSourceName": "USB-PD",
                         "WinningPowerSourceOption": ["Voltage (mV)": 20000, "Max Current (mA)": 4700,
                                                      "Max Power (mW)": 94000]])
        let raw = F.raw(
            ports: [F.port(id: 1, number: 1, connected: true), F.port(id: 2, number: 2, connected: true),
                    F.port(id: 3, number: 3, connected: true), powerSource],
            usb: [F.usb(id: 50, name: "Drive", location: 0x0310_0000, allocation: 900, path: "x/Port-USB-C@3")],
            battery: ["ExternalConnected": true, "BatteryInstalled": true, "AdapterDetails": .dict(Self.adapter96.values),
                      "PowerTelemetryData": ["SystemPowerIn": 61000, "SystemLoad": 12000, "BatteryPower": 45000]],
            uuids: ["2/1": "8C1E2D3A-0000-4000-8000-000000000001",
                    "2/2": "8c1e2d3a-0000-4000-8000-000000000002",
                    "2/3": "8C1E2D3A00004000800000000000 0003"],
            smc: [SMCChannel(index: 1, uuid: "8c1e2d3a000040008000000000000002", volts: 19.8, amps: 3.05, present: true),
                  SMCChannel(index: 3, uuid: "8C1E2D3A000040008000000000000001", volts: 5.05, amps: 0.9, present: true),
                  // Port 3: a reading below 50 mW is ignored.
                  SMCChannel(index: 2, uuid: "8c1e2d3a000040008000000000000003", volts: 0.02, amps: 0.5),
                  SMCChannel(index: 4, uuid: "ffff", volts: 5, amps: 3)])
        let snapshot = TopologyBuilder.build(raw)

        let port1 = try #require(snapshot.port(PortKey(type: 2, number: 1))?.power)
        #expect(port1.direction == .output)
        #expect(port1.source == .smc)
        #expect(port1.milliwatts == 4545)
        #expect(port1.millivolts == 5050)
        #expect(port1.milliamps == 900)
        #expect(port1.isMeasured)

        let port2 = try #require(snapshot.port(PortKey(type: 2, number: 2)))
        #expect(port2.charger?.name == "96W USB-C Power Adapter")
        #expect(port2.power?.direction == .input)
        #expect(port2.power?.source == .smc)
        #expect(port2.power?.milliwatts == 60390)

        let port3 = try #require(snapshot.port(PortKey(type: 2, number: 3))?.power)
        #expect(port3.source == .usbAllocation)
        #expect(port3.milliwatts == 4500)

        #expect(snapshot.power.portOutputMilliwatts == 4545 + 4500)
        #expect(snapshot.power.usbAllocatedMilliwatts == 4500)
        #expect(snapshot.power.charger?.portKey == PortKey(type: 2, number: 2))
        #expect(snapshot.power.charger?.millivolts == 20000)
        #expect(snapshot.power.charger?.activeProfile?.millivolts == 20000)
        #expect(snapshot.power.charger?.familyDescription == "USB-C PD")
    }

    @Test func sharedControllerUUIDJoinsNothing() {
        let raw = F.raw(ports: [F.port(id: 1, number: 1, connected: true), F.port(id: 2, number: 2, connected: true)],
                        uuids: ["2/1": "AA", "2/2": "aa"],
                        smc: [SMCChannel(index: 1, uuid: "aa", volts: 5, amps: 1)])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.ports.allSatisfy { $0.power == nil })
    }

    // MARK: PowerOutDetails and MagSafe

    @Test func powerOutDetailsJoinByPortIndexNeverMagSafe() throws {
        let raw = F.raw(
            ports: [F.port(id: 10, type: 17, number: 1, description: "MagSafe 3", connected: true, supported: ["CC"]),
                    F.port(id: 11, number: 1, connected: true),
                    F.port(id: 12, number: 2, connected: true, extra: ["FeaturesEnabled": ["TRM", "Power In"]])],
            battery: ["ExternalConnected": true, "BatteryInstalled": true,
                      "PowerTelemetryData": ["SystemPowerIn": 93000, "SystemLoad": 20000],
                      "PowerOutDetails": [["PortIndex": 2, "Watts": 4500, "AdapterVoltage": 5000, "Current": 900],
                                          ["PortIndex": 1, "Watts": 2250],
                                          // No index: offset + 1 = 3, which does not exist.
                                          ["PortIndex": 0, "Watts": 1000],
                                          ["PortIndex": 1, "Watts": 0]]],
            adapter: ["Watts": 140, "Name": "140W USB-C Power Adapter", "FamilyCode": .int(-536854518),
                      "AdapterVoltage": 28000, "Current": 5000])
        let snapshot = TopologyBuilder.build(raw)

        let magSafe = try #require(snapshot.port(PortKey(type: 17, number: 1)))
        #expect(magSafe.charger?.name == "140W USB-C Power Adapter")
        #expect(magSafe.power?.direction == .input)
        #expect(magSafe.power?.source == .telemetry)
        #expect(magSafe.power?.milliwatts == 93000)

        let usbC1 = try #require(snapshot.port(PortKey(type: 2, number: 1))?.power)
        #expect(usbC1.source == .powerOutDetails)
        #expect(usbC1.milliwatts == 2250)
        #expect(usbC1.direction == .output)

        let usbC2 = try #require(snapshot.port(PortKey(type: 2, number: 2)))
        // "Power In" is weaker evidence than a connected MagSafe charger.
        #expect(usbC2.charger == nil)
        #expect(usbC2.power?.milliwatts == 4500)
        #expect(usbC2.power?.millivolts == 5000)
        #expect(usbC2.power?.milliamps == 900)

        #expect(snapshot.power.portOutputMilliwatts == 6750)
        #expect(snapshot.power.systemInputMilliwatts == 93000)
        #expect(snapshot.power.charger?.contractMilliwatts == 140000)
    }

    @Test func powerOutDetailsParser() {
        let parsed = PowerParser.powerOutDetails(["PowerOutDetails": [["Watts": 1500], ["PortIndex": "x", "Watts": 2000],
                                                                      ["PortIndex": 4, "Watts": -3],
                                                                      ["PortIndex": 4, "Watts": 99_999_999]]])
        #expect(parsed[1]?.milliwatts == 1500)
        #expect(parsed[2]?.milliwatts == 2000)
        #expect(parsed[4] == nil)
    }

    // MARK: Telemetry and battery

    @Test func negativeTelemetryValues() throws {
        let raw = F.raw(
            ports: [F.port(id: 1, number: 1, connected: true, extra: ["FeaturesEnabled": ["Power In"]])],
            battery: ["ExternalConnected": true, "BatteryInstalled": true, "IsCharging": false,
                      "CurrentCapacity": 81, "MaxCapacity": 100, "NotChargingReason": 4,
                      "AdapterDetails": ["Watts": 20, "AdapterVoltage": 9000, "Current": 2220],
                      "PowerTelemetryData": [
                          // Unsigned encodings of -4096, -2000 and a plain negative.
                          "BatteryPower": .double(18_446_744_073_709_547_520.0),
                          "SystemPowerIn": .string("18446744073709549616"),
                          "SystemLoad": .int(-5),
                      ]])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.power.battery?.powerMilliwatts == -4096)
        #expect(snapshot.power.battery?.percent == 81)
        #expect(snapshot.power.battery?.notChargingReason == 4)
        #expect(snapshot.power.battery?.statusText == "Not charging · 81%")
        // Negative input or load make no sense: clamped to zero.
        #expect(snapshot.power.systemInputMilliwatts == 0)
        #expect(snapshot.power.systemLoadMilliwatts == 0)
        // With no measured input, the charger port shows the contract.
        let port = try #require(snapshot.ports.first)
        #expect(port.power?.source == .pdContract)
        #expect(port.power?.milliwatts == 19980)
        #expect(port.power?.millivolts == 9000)
        #expect(port.power?.milliamps == 2220)
    }

    @Test func batteryPercentages() {
        func percent(_ current: PlistValue, _ maximum: PlistValue) -> Int? {
            PowerParser.battery(F.raw(battery: ["CurrentCapacity": current, "MaxCapacity": maximum]),
                                telemetry: .init())?.percent
        }
        #expect(percent(34, 100) == 34)
        #expect(percent(4000, 5000) == 80)
        #expect(percent(6000, 5000) == 100)
        #expect(percent(-5, 100) == 0)
        #expect(percent(50, 0) == nil)
        #expect(percent("full", 100) == nil)
    }

    @Test func noChargerWhenUnplugged() {
        // ExternalConnected = No and nothing in the adapter dictionaries.
        let unplugged = TopologyBuilder.build(F.raw(
            ports: [F.port(id: 1, number: 1)],
            battery: ["ExternalConnected": false, "BatteryInstalled": true, "AdapterDetails": ["FamilyCode": 0]]))
        #expect(unplugged.power.charger == nil)
        #expect(unplugged.power.battery?.statusText == "On battery")

        // Stale AdapterDetails while unplugged are ignored too.
        let stale = TopologyBuilder.build(F.raw(
            battery: ["ExternalConnected": false, "AdapterDetails": .dict(Self.adapter96.values)]))
        #expect(stale.power.charger == nil)

        // The IOPS dictionary is empty when nothing is attached, so it is trusted.
        let ioPS = TopologyBuilder.build(F.raw(battery: ["ExternalConnected": false], adapter: Self.adapter96))
        #expect(ioPS.power.charger?.ratedWatts == 96)
        #expect(ioPS.power.charger?.portKey == nil)
    }

    @Test func chargerFromPortEvidenceAlone() throws {
        // ExternalConnected but no adapter dictionaries: the Apple charger's
        // own identity and the winning power source fill in.
        let raw = F.raw(ports: [
            F.port(id: 1, number: 1, connected: true),
            F.node(id: 2, parent: 1, className: "IOPortTransportProtocolAppleUVDM", name: "AppleUVDM",
                   properties: ["User String": "35W Dual USB-C Port Power Adapter", "Vendor": "Apple Inc.",
                                "Serial Number": "C4H0000", "ParentPortType": 2, "ParentPortNumber": 1]),
            F.node(id: 3, parent: 1, className: "IOPortFeaturePowerSource", name: "TypeC [*]",
                   properties: ["WinningPowerSourceOption": ["Voltage (mV)": 5000, "Max Current (mA)": 3000]]),
        ], battery: ["ExternalConnected": true, "BatteryInstalled": true])
        let charger = try #require(TopologyBuilder.build(raw).power.charger)
        #expect(charger.name == "35W Dual USB-C Port Power Adapter")
        #expect(charger.manufacturer == "Apple Inc.")
        #expect(charger.serialNumber == "C4H0000")
        #expect(charger.millivolts == 5000)
        #expect(charger.milliamps == 3000)
        #expect(charger.portKey == PortKey(type: 2, number: 1))
    }

    @Test func winningPowerSourceIsReadFirst() throws {
        func source(_ id: UInt64, _ name: String, millivolts: Int) -> RawNode {
            F.node(id: id, parent: 1, className: "IOPortFeaturePowerSource", name: name,
                   properties: ["WinningPowerSourceOption": ["Voltage (mV)": .int(Int64(millivolts)),
                                                             "Max Current (mA)": 3000]])
        }
        let nodes = [F.port(id: 1, number: 1, connected: true), source(2, "TypeC", millivolts: 5000),
                     source(9, "USB-PD [*]", millivolts: 15000)]
        for order in [nodes, nodes.reversed()] {
            let raw = F.raw(ports: order, battery: ["ExternalConnected": true])
            #expect(TopologyBuilder.build(raw).power.charger?.millivolts == 15000)
        }
    }

    @Test func magSafeFamilyFallback() throws {
        let raw = F.raw(ports: [F.port(id: 1, type: 17, number: 1, description: "MagSafe 3", connected: true)],
                        battery: ["ExternalConnected": true], adapter: ["Watts": 70])
        let charger = try #require(TopologyBuilder.build(raw).power.charger)
        #expect(charger.familyDescription == "MagSafe")
        #expect(charger.displayName == "70W Power Adapter")
    }

    @Test func desktopWithoutBattery() {
        let raw = F.raw(hasBattery: false,
                        battery: ["BatteryInstalled": false, "ExternalConnected": true,
                                  "PowerTelemetryData": ["SystemPowerIn": 40000, "SystemLoad": 39000]])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.power.battery == nil)
        #expect(!snapshot.power.hasBattery)
        #expect(!snapshot.machine.isLaptop)
        #expect(snapshot.power.charger == nil)
        #expect(snapshot.power.systemInputMilliwatts == 40000)
        #expect(snapshot.power.systemLoadMilliwatts == 39000)
    }

    @Test func familyCodes() {
        #expect(PowerParser.familyDescription(-536854518) == "USB-C PD")
        #expect(PowerParser.familyDescription(0xE000_400A) == "USB-C PD")
        #expect(PowerParser.familyDescription(0xE001_0000) == "AC adapter")
        #expect(PowerParser.familyDescription(0) == nil)
        #expect(PowerParser.familyDescription(nil) == nil)
        #expect(PowerParser.familyDescription(42) == nil)
    }

    @Test func profilesSkipBadEntries() {
        let profiles = PowerParser.profiles([
            "UsbHvcHvcIndex": 1,
            "UsbHvcMenu": [["Index": 1, "MaxVoltage": 15000, "MaxCurrent": 3000],
                           ["Index": 0, "MaxVoltage": 5000, "MaxCurrent": 3000],
                           ["Index": 0, "MaxVoltage": 5000, "MaxCurrent": 1500],
                           ["Index": 2, "MaxVoltage": "lots", "MaxCurrent": 3000],
                           ["Index": 3, "MaxVoltage": .int(Int64.max), "MaxCurrent": 3000],
                           "not a dictionary"],
        ])
        #expect(profiles.map(\.index) == [0, 1])
        #expect(profiles.first { $0.isActive }?.label == "15 V × 3 A")
        #expect(profiles.first?.maxMilliwatts == 15000)
    }
}
