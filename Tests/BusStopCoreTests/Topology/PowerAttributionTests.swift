import Foundation
import Testing
@testable import BusStopCore

/// Which port charges the Mac when several could, SMC channels joined by
/// elimination, stale `PowerOutDetails` and the power the Mac itself supplies.
@Suite("Topology: power attribution")
struct PowerAttributionTests {
    typealias F = TopologyFixtures

    static let battery: PropertyBag = [
        "ExternalConnected": true, "BatteryInstalled": true,
        "PowerTelemetryData": ["SystemPowerIn": 58000, "SystemLoad": 20000],
    ]

    /// An `IOPortFeaturePowerSource` on USB-C `number` holding a winning option.
    static func winning(id: UInt64, port: Int, type: Int = 2, name: String = "USB-PD [*]",
                        maxPower: Int) -> RawNode {
        F.node(id: id, parent: nil, className: "IOPortFeaturePowerSource", name: name,
               properties: ["ParentPortType": .int(Int64(type)), "ParentPortNumber": .int(Int64(port)),
                            "PowerSourceName": "USB-PD",
                            "WinningPowerSourceOption": ["Voltage (mV)": 20000,
                                                         "Max Current (mA)": .int(Int64(maxPower / 20)),
                                                         "Max Power (mW)": .int(Int64(maxPower))]])
    }

    static func magSafe(connected: Bool = true) -> RawNode {
        F.port(id: 1, type: 17, number: 1, description: "MagSafe 3", connected: connected, supported: ["CC"])
    }

    // MARK: Charger port

    @Test func winningContractBeatsAConnectedMagSafe() throws {
        let raw = F.raw(ports: [Self.magSafe(), F.port(id: 2, number: 2, connected: true),
                                Self.winning(id: 20, port: 2, maxPower: 60000)],
                        battery: Self.battery,
                        adapter: ["Watts": 60, "Name": "USB-C Power Adapter"])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.power.charger?.portKey == PortKey(type: 2, number: 2))
        let port = try #require(snapshot.port(PortKey(type: 2, number: 2)))
        #expect(port.power?.direction == .input)
        #expect(port.charger != nil)
        let magSafe = try #require(snapshot.port(PortKey(type: 17, number: 1)))
        #expect(magSafe.charger == nil)
        #expect(magSafe.power?.direction != .input)
    }

    @Test func severalContractsFollowTheAdapter() {
        // A USB-C monitor offers 15 W on port 1; the 96 W adapter is on port 2.
        let ports = [F.port(id: 1, number: 1, connected: true), F.port(id: 2, number: 2, connected: true),
                     Self.winning(id: 10, port: 1, maxPower: 15000), Self.winning(id: 20, port: 2, maxPower: 94000)]
        let matched = TopologyBuilder.build(F.raw(ports: ports, battery: Self.battery, adapter: ["Watts": 96]))
        #expect(matched.power.charger?.portKey == PortKey(type: 2, number: 2))

        // Without the adapter's rating, the most power wins.
        let most = TopologyBuilder.build(F.raw(ports: ports, battery: Self.battery,
                                               adapter: ["Name": "USB-C Power Adapter"]))
        #expect(most.power.charger?.portKey == PortKey(type: 2, number: 2))

        // The adapter's rating beats a bigger contract elsewhere.
        let small = TopologyBuilder.build(F.raw(ports: ports, battery: Self.battery, adapter: ["Watts": 15]))
        #expect(small.power.charger?.portKey == PortKey(type: 2, number: 1))
    }

    @Test func tiedContractsLeaveTheChargerWithoutAPort() {
        let ports = [F.port(id: 1, number: 1, connected: true), F.port(id: 2, number: 2, connected: true),
                     Self.winning(id: 10, port: 1, maxPower: 60000), Self.winning(id: 20, port: 2, maxPower: 60000)]
        let snapshot = TopologyBuilder.build(F.raw(ports: ports, battery: Self.battery,
                                                   adapter: ["Watts": 96, "Name": "96W USB-C Power Adapter"]))
        #expect(snapshot.power.charger != nil)
        #expect(snapshot.power.charger?.portKey == nil)
        #expect(snapshot.ports.allSatisfy { $0.charger == nil && $0.power?.direction != .input })
    }

    @Test func markedContractBeatsAnUnmarkedOne() {
        let ports = [F.port(id: 1, number: 1, connected: true), F.port(id: 2, number: 2, connected: true),
                     Self.winning(id: 10, port: 1, name: "USB-PD", maxPower: 94000),
                     Self.winning(id: 20, port: 2, maxPower: 30000)]
        let snapshot = TopologyBuilder.build(F.raw(ports: ports, battery: Self.battery, adapter: ["Watts": 96]))
        #expect(snapshot.power.charger?.portKey == PortKey(type: 2, number: 2))
    }

    // MARK: SMC join by elimination

    static let uuids = (magSafe: "AAAAAAAA-0000-4000-8000-000000000001", port1: "BBBBBBBB-0000-4000-8000-000000000002",
                        spare: "cccccccc000040008000000000000003")

    /// The M2 shape: MagSafe and USB-C 1 publish their HPM UUID, USB-C 2
    /// publishes a blank one; D1 = USB-C 1, D2 = the spare, D3 = MagSafe.
    static func m2(ports: [RawNode]? = nil, uuids: [String: String]? = nil, channels: [SMCChannel]? = nil) -> RawSnapshot {
        F.raw(ports: ports ?? [Self.magSafe(connected: false), F.port(id: 2, number: 1, connected: true),
                               F.port(id: 3, number: 2, connected: true)],
              battery: ["ExternalConnected": false, "BatteryInstalled": true],
              uuids: uuids ?? ["17/1": Self.uuids.magSafe, "2/1": Self.uuids.port1],
              smc: channels ?? [
                  SMCChannel(index: 1, uuid: PowerParser.normalizedUUID(Self.uuids.port1), volts: 5, amps: 0.5),
                  SMCChannel(index: 2, uuid: Self.uuids.spare, volts: 5.1, amps: 1),
                  SMCChannel(index: 3, uuid: PowerParser.normalizedUUID(Self.uuids.magSafe), volts: 0, amps: 0),
              ])
    }

    @Test func blankControllerUUIDJoinsTheSpareChannel() throws {
        let snapshot = TopologyBuilder.build(Self.m2())
        let port2 = try #require(snapshot.port(PortKey(type: 2, number: 2))?.power)
        #expect(port2.source == .smc)
        #expect(port2.milliwatts == 5100)
        #expect(snapshot.port(PortKey(type: 2, number: 1))?.power?.milliwatts == 2500)
    }

    @Test func eliminationRefusesWhenAnythingIsOff() {
        func port2Power(_ raw: RawSnapshot) -> PortPower? {
            TopologyBuilder.build(raw).port(PortKey(type: 2, number: 2))?.power
        }
        // Two ports without a UUID.
        #expect(port2Power(Self.m2(uuids: ["17/1": Self.uuids.magSafe])) == nil)
        // Two spare channels.
        #expect(port2Power(Self.m2(channels: [
            SMCChannel(index: 1, uuid: "dddd", volts: 5, amps: 0.5),
            SMCChannel(index: 2, uuid: Self.uuids.spare, volts: 5.1, amps: 1),
            SMCChannel(index: 3, uuid: PowerParser.normalizedUUID(Self.uuids.magSafe), volts: 0, amps: 0),
        ])) == nil)
        // More channels than USB-C and MagSafe ports.
        #expect(port2Power(Self.m2(channels: [
            SMCChannel(index: 1, uuid: PowerParser.normalizedUUID(Self.uuids.port1), volts: 5, amps: 0.5),
            SMCChannel(index: 2, uuid: Self.uuids.spare, volts: 5.1, amps: 1),
            SMCChannel(index: 3, uuid: PowerParser.normalizedUUID(Self.uuids.magSafe), volts: 0, amps: 0),
            SMCChannel(index: 4, uuid: nil, volts: 0, amps: 0),
        ])) == nil)
        // The spare channel's index is not the port's rank.
        #expect(port2Power(Self.m2(channels: [
            SMCChannel(index: 1, uuid: Self.uuids.spare, volts: 5.1, amps: 1),
            SMCChannel(index: 2, uuid: PowerParser.normalizedUUID(Self.uuids.port1), volts: 5, amps: 0.5),
            SMCChannel(index: 3, uuid: PowerParser.normalizedUUID(Self.uuids.magSafe), volts: 0, amps: 0),
        ])) == nil)
    }

    // MARK: PowerOutDetails

    @Test func stalePowerOutDetailsNeedAConnectedPort() throws {
        let battery: PropertyBag = ["ExternalConnected": false, "BatteryInstalled": true,
                                    "PowerOutDetails": [["PortIndex": 1, "Watts": 6098],
                                                        ["PortIndex": 2, "Watts": 4500]]]
        let raw = F.raw(ports: [F.port(id: 1, number: 1), F.port(id: 2, number: 2, connected: true)],
                        battery: battery)
        let snapshot = TopologyBuilder.build(raw)
        let port1 = try #require(snapshot.port(PortKey(type: 2, number: 1)))
        #expect(!port1.isConnected)
        #expect(port1.power == nil)
        #expect(snapshot.port(PortKey(type: 2, number: 2))?.power?.source == .powerOutDetails)
        #expect(snapshot.power.portOutputMilliwatts == 4500)
    }

    @Test func liveSMCZeroOutranksPowerOutDetails() {
        let battery: PropertyBag = ["ExternalConnected": false, "BatteryInstalled": true,
                                    "PowerOutDetails": [["PortIndex": 1, "Watts": 6098]]]
        let uuid = "EEEEEEEE-0000-4000-8000-000000000001"
        let reading = { (channel: SMCChannel) -> PortPower? in
            TopologyBuilder.build(F.raw(ports: [F.port(id: 1, number: 1, connected: true)], battery: battery,
                                        uuids: ["2/1": uuid], smc: [channel]))
                .port(PortKey(type: 2, number: 1))?.power
        }
        #expect(reading(SMCChannel(index: 1, uuid: uuid, volts: 0, amps: 0)) == nil)
        // An SMC channel without readings does not overrule it.
        #expect(reading(SMCChannel(index: 1, uuid: uuid))?.source == .powerOutDetails)
    }

    // MARK: Power the Mac supplies

    @Test func dockAndDisplayPortsReportNoMacSuppliedPower() throws {
        let snapshot = TopologyBuilder.build(ThunderboltTopologyTests.raw())
        for number in [1, 2] {
            let port = try #require(snapshot.port(PortKey(type: 2, number: number)))
            #expect(port.power == nil)
            #expect(port.hostAllocatedMilliwatts == 0)
            #expect(port.allocatedMilliwatts > 0)
        }
        let dock = try #require(DemoTestSupport.snapshot(.dockStation).port(PortKey(type: 2, number: 3)))
        #expect(dock.hostAllocatedMilliwatts == 0)
        #expect(dock.allocatedMilliwatts > 0)
        #expect(dock.power?.source == .smc)
        let front = try #require(DemoTestSupport.snapshot(.dockStation).port(PortKey(type: 2, number: 1)))
        #expect(front.hostAllocatedMilliwatts == front.power?.milliwatts)
    }
}
