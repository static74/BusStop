import Foundation
import Testing
@testable import BusStopCore

/// The builder against a real capture (see `MacBookNeoFixture`).
///
/// `Mac17,5` is in the port catalogue, so these tests never assert location
/// names or label sources, only connectors and numbers.
@Suite("Topology: MacBook Neo capture")
struct MacBookNeoTopologyTests {
    let snapshot = TopologyBuilder.build(MacBookNeoFixture.raw())

    var port1: PhysicalPort? { snapshot.port(PortKey(type: 2, number: 1)) }
    var port2: PhysicalPort? { snapshot.port(PortKey(type: 2, number: 2)) }

    @Test func batteryFixtureDecodes() {
        let battery = MacBookNeoFixture.battery
        #expect(battery.bag("AdapterDetails")?.string("Name") == "30W USB-C Power Adapter")
        #expect(battery.bag("PowerTelemetryData")?.int("SystemPowerIn") == 28217)
    }

    @Test func findsTheTwoUSBCPortsAndSkipsTheInductiveOne() {
        #expect(snapshot.ports.map(\.key) == [PortKey(type: 2, number: 1), PortKey(type: 2, number: 2)])
        #expect(snapshot.ports.allSatisfy { $0.kind == .usbC })
        #expect(port1?.registryName == "Port-USB-C@1")
        #expect(port2?.registryName == "Port-USB-C@2")
        #expect(port1?.label.connector == "USB-C")
        #expect(port2?.label.number == 2)
        #expect(snapshot.captureNotes.isEmpty)
    }

    @Test func port2CarriesUSB2AndIgnoresStaleSuperSpeedFlag() throws {
        let port = try #require(port2)
        #expect(port.isConnected)
        #expect(port.supportedTransports == [.usb2])
        #expect(port.activeTransports.map(\.kind) == [.usb2])
        let usb2 = try #require(port.activeTransports.first)
        #expect(usb2.isActive)
        #expect(!usb2.isTunneled)
        #expect(usb2.productName == "CT4000X10PROSSD9")
        #expect(usb2.link?.generation == "USB 2.0")
        #expect(usb2.link?.bitsPerSecond == 480_000_000)
        #expect(usb2.link?.detail == "480 Mbps (High Speed)")
        #expect(port.link?.label == "USB 2.0 @ 480 Mb/s")
        #expect(port.statistics == PortStatistics(connectionCount: 2, plugEventCount: 2, overcurrentCount: 0))
        #expect(!port.liquidDetected)
        #expect(port.cable == nil)
        #expect(port.charger == nil)
    }

    @Test func ssdHangsOffPort2ThroughItsTransport() throws {
        let port = try #require(port2)
        #expect(port.devices.count == 1)
        let ssd = try #require(port.devices.first)
        #expect(ssd.id == "usb:00110000:0634:5604")
        #expect(ssd.registryID == MacBookNeoFixture.ssdID)
        #expect(ssd.bus == .usb)
        #expect(ssd.kind == .storage)
        #expect(ssd.name == "CT4000X10PROSSD9")
        #expect(ssd.vendorName == "Micron")
        #expect(ssd.vendorID == 1588)
        #expect(ssd.productID == 22020)
        #expect(ssd.serialNumber == "2407E8CE7167")
        #expect(ssd.usbVersion == "2.1")
        #expect(ssd.deviceClass == 0)
        #expect(ssd.locationID == 0x0011_0000)
        #expect(ssd.link?.label == "USB 2.0 @ 480 Mb/s")
        #expect(ssd.power?.allocatedMilliwatts == 2500)
        #expect(ssd.power?.source == .usbAllocation)
        #expect(!ssd.isTunneled)
        #expect(ssd.children.isEmpty)
        // Raw properties are copied without driver plumbing.
        #expect(ssd.properties?.has("UsbLinkSpeed") == true)
        #expect(ssd.properties?.has("IOProbeScore") == false)
        #expect(snapshot.otherDevices.isEmpty)
        #expect(snapshot.deviceCount == 1)
    }

    @Test func port1HasOnlyTheChargerOnCC() throws {
        let port = try #require(port1)
        #expect(port.isConnected)
        #expect(port.activeTransports.isEmpty)
        #expect(port.link == nil)
        #expect(port.supportedTransports == [.usb3, .displayPort, .usb2])
        #expect(port.devices.isEmpty)
        #expect(port.statistics?.connectionCount == 3)
    }

    @Test func chargerIsTiedToPort1AndPrefersAdapterDetails() throws {
        let charger = try #require(snapshot.power.charger)
        #expect(charger.portKey == PortKey(type: 2, number: 1))
        #expect(charger.name == "30W USB-C Power Adapter")
        #expect(charger.manufacturer == "Apple Inc.")
        #expect(charger.ratedWatts == 30)
        #expect(charger.millivolts == 20000)
        #expect(charger.milliamps == 1490)
        #expect(charger.familyDescription == "USB-C PD")
        #expect(!charger.isWireless)
        #expect(charger.serialNumber == "<redacted>")
        #expect(charger.profiles.map(\.index) == [0, 1, 2, 3])
        #expect(charger.profiles.map(\.millivolts) == [5000, 9000, 15000, 20000])
        #expect(charger.profiles.map(\.maxMilliamps) == [2960, 2980, 1990, 1490])
        #expect(charger.activeProfile?.index == 3)
        #expect(charger.contractMilliwatts == 29800)
        #expect(port1?.charger == charger)
    }

    @Test func powerFiguresComeFromTelemetryAndAllocations() throws {
        let input = try #require(port1?.power)
        #expect(input.direction == .input)
        #expect(input.milliwatts == 28217)
        #expect(input.source == .telemetry)

        let output = try #require(port2?.power)
        #expect(output.direction == .output)
        #expect(output.milliwatts == 2500)
        #expect(output.source == .usbAllocation)

        let summary = snapshot.power
        #expect(summary.systemInputMilliwatts == 28217)
        #expect(summary.systemLoadMilliwatts == 4230)
        #expect(summary.portOutputMilliwatts == 2500)
        #expect(summary.usbAllocatedMilliwatts == 2500)
        #expect(summary.hasBattery)
    }

    @Test func batteryState() throws {
        let battery = try #require(snapshot.power.battery)
        #expect(battery.percent == 34)
        #expect(battery.isCharging)
        #expect(!battery.isFullyCharged)
        #expect(battery.externalConnected)
        #expect(battery.notChargingReason == 0)
        #expect(battery.powerMilliwatts == 23987)
        #expect(battery.statusText == "Charging · 34%")
    }

    @Test func machineSummary() {
        #expect(snapshot.machine.model == "Mac17,5")
        #expect(snapshot.machine.isLaptop)
        #expect(snapshot.machine.chip == "Apple A18 Pro")
        #expect(!snapshot.machine.name.isEmpty)
        #expect(snapshot.capturedAt == TopologyFixtures.date)
    }

    @Test func rawPropertiesCanBeLeftOut() {
        let lean = TopologyBuilder.build(MacBookNeoFixture.raw(), options: BuildOptions(includeRawProperties: false))
        #expect(lean.ports.allSatisfy { $0.properties == nil })
        #expect(lean.allDevices.allSatisfy { $0.device.properties == nil })
        #expect(lean.ports.map(\.key) == snapshot.ports.map(\.key))
    }

    @Test func demoFlagIsCarried() {
        #expect(!snapshot.isDemo)
        #expect(TopologyBuilder.build(MacBookNeoFixture.raw(), options: BuildOptions(isDemo: true)).isDemo)
    }
}
