import Foundation
import Testing
@testable import BusStopCore

@Suite("Demo scenarios: studio desk")
struct DemoStudioDeskTests {
    typealias S = DemoTestSupport
    let snapshot = S.snapshot(.studioDesk)

    @Test func machineAndPortLabels() {
        #expect(snapshot.machine.model == "Mac17,9")
        #expect(snapshot.machine.name == "MacBook Pro (14-inch, 2026, M5 Pro)")
        #expect(snapshot.machine.chip == "Apple M5 Pro")
        #expect(snapshot.machine.isLaptop)
        #expect(snapshot.isDemo)
        #expect(snapshot.ports.map(\.label.title) == [
            "Left Rear · MagSafe", "Left Center · USB-C", "Left Front · USB-C", "Right Rear · HDMI",
            "Right Center · USB-C",
        ])
        #expect(snapshot.ports.allSatisfy { $0.label.source == .catalog })
        #expect(snapshot.connectedPorts.map(\.key.description) == ["17/1", "2/1", "2/2"])
        #expect(snapshot.ports.first { $0.kind == .usbC }?.capabilityDescription == "Thunderbolt 5")
        #expect(snapshot.otherDevices.isEmpty)
        #expect(snapshot.deviceCount == 8)
    }

    @Test func magSafeCharger() throws {
        let magSafe = try #require(S.port(snapshot, 17, 1))
        let charger = try #require(magSafe.charger)
        #expect(charger.name == "140W USB-C Power Adapter")
        #expect(charger.manufacturer == "Apple Inc.")
        #expect(charger.ratedWatts == 140)
        #expect(charger.millivolts == 28_000)
        #expect(charger.milliamps == 5_000)
        #expect(charger.familyDescription == "USB-C PD")
        #expect(charger.profiles.map(\.label) == ["5 V × 3 A", "9 V × 3 A", "15 V × 3 A", "20 V × 4.7 A", "28 V × 5 A"])
        #expect(charger.activeProfile?.index == 4)
        #expect(snapshot.power.charger == charger)

        let power = try #require(magSafe.power)
        #expect(power.direction == .input)
        #expect(power.source == .smc)
        #expect(S.isNear(power.milliwatts, 62_000, within: 0.03))
        #expect(S.isNear(snapshot.power.systemInputMilliwatts, 62_000, within: 0.03))
        #expect(power.millivolts.map { (27_800...28_100).contains($0) } == true)

        let battery = try #require(snapshot.power.battery)
        #expect(battery.percent == 76)
        #expect(battery.isCharging)
        #expect(battery.externalConnected)
        #expect(battery.statusText == "Charging · 76%")
        #expect((battery.powerMilliwatts ?? 0) > 15_000)
    }

    @Test func studioDisplayOverThunderbolt5() throws {
        let port = try #require(S.port(snapshot, 2, 1))
        #expect(port.isConnected)
        #expect(port.activeTransports.map(\.kind) == [.cio, .usb2])
        let link = try #require(port.link)
        #expect(link.label == "USB4 v2 / TB5 @ 80 Gb/s")
        #expect(link.detail == "2 × 40 Gb/s")
        #expect(port.power == nil)

        let cable = try #require(port.cable)
        #expect(cable.isActive == false)
        #expect(cable.typeDescription == "Passive Cable")
        #expect(cable.speedDescription == "USB4 Gen 4 (80 Gb/s)")
        #expect(cable.currentRatingMilliamps == 5_000)
        #expect(cable.vendorID == 0x05AC)

        #expect(port.devices.count == 1)
        let display = try #require(port.devices.first)
        #expect(display.name == "Studio Display XDR")
        #expect(display.bus == .thunderbolt)
        #expect(display.kind == .display)
        #expect(display.chainDepth == 1)
        #expect(display.id == "tb:05ac2b448d100f01")
        #expect(display.link?.label == "USB4 v2 / TB5 @ 80 Gb/s")

        let hub = try #require(display.children.first)
        #expect(display.children.count == 1)
        #expect(hub.name == "Studio Display XDR Hub")
        #expect(hub.kind == .hub)
        #expect(hub.isTunneled)
        #expect(hub.link?.label == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(hub.power?.isSelfPowered == true)
        #expect(hub.children.map(\.name) == ["PSSD T9", "Studio Display XDR Camera"])

        let ssd = try #require(hub.children.first)
        #expect(ssd.kind == .storage)
        #expect(ssd.vendorName == "Samsung")
        #expect(ssd.link?.label == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(ssd.usbVersion == "3.2")
        #expect(ssd.isTunneled)
        #expect(ssd.power?.allocatedMilliwatts == 4_480)

        let camera = try #require(hub.children.last)
        #expect(camera.kind == .camera)
        #expect(camera.link?.label == "USB 2.0 @ 480 Mb/s")
        // The display powers its own hub, so nothing counts against the Mac's port.
        #expect(display.rolledUpMilliwatts == 0)
    }

    @Test func usbCHubWithKeyboardMouseAndFlashDrive() throws {
        let port = try #require(S.port(snapshot, 2, 2))
        #expect(port.activeTransports.map(\.kind) == [.usb3, .usb2])
        #expect(port.link?.label == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(port.devices.count == 1)
        let hub = try #require(port.devices.first)
        #expect(hub.name == "USB3.1 Hub")
        #expect(hub.vendorName == "VIA Labs, Inc.")
        #expect(hub.kind == .hub)
        #expect(hub.link?.label == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(hub.power?.isSelfPowered == false)
        #expect(hub.children.map(\.name) == ["DataTraveler 3.0", "Keychron K8 Pro", "USB Optical Mouse"])
        #expect(hub.descendantCount == 3)
        // Hub 0.5 W, keyboard 0.5 W, mouse 0.5 W, flash drive 2.5 W.
        #expect(hub.rolledUpMilliwatts == 4_000)
        #expect(port.allocatedMilliwatts == 4_000)

        let devices = S.devices(snapshot)
        #expect(devices["Keychron K8 Pro"]?.kind == .keyboard)
        #expect(devices["Keychron K8 Pro"]?.link?.label == "USB 1.1 Full Speed @ 12 Mb/s")
        #expect(devices["Keychron K8 Pro"]?.power?.allocatedMilliwatts == 500)
        #expect(devices["USB Optical Mouse"]?.kind == .mouse)
        #expect(devices["USB Optical Mouse"]?.power?.allocatedMilliwatts == 500)
        #expect(devices["DataTraveler 3.0"]?.kind == .storage)
        #expect(devices["DataTraveler 3.0"]?.usbVersion == "3.0")
        #expect(devices["DataTraveler 3.0"]?.link?.label == "USB 2.0 @ 480 Mb/s")

        // The SMC measures about 4 W out of the hub port.
        let power = try #require(port.power)
        #expect(power.direction == .output)
        #expect(power.source == .smc)
        #expect(S.isNear(power.milliwatts, 3_950, within: 0.035))
        #expect(snapshot.power.usbAllocatedMilliwatts == 4_000)
    }

    @Test func emptyPorts() throws {
        for key in [PortKey(type: 2, number: 3), PortKey(type: 6, number: 1)] {
            let port = try #require(snapshot.port(key))
            #expect(!port.isConnected)
            #expect(port.devices.isEmpty)
            #expect(port.power == nil)
            #expect(port.link == nil)
        }
        #expect(S.port(snapshot, 2, 3)?.label.title == "Right Center · USB-C")
    }

    @Test func displaysAreAttributed() throws {
        #expect(snapshot.displays.map(\.name) == ["Built-in Liquid Retina XDR Display", "Studio Display XDR"])
        let builtIn = try #require(snapshot.displays.first)
        #expect(builtIn.isBuiltin)
        #expect(builtIn.portKey == nil)
        #expect(builtIn.modeDescription == "3024 × 1964 @ 120 Hz")
        let xdr = try #require(snapshot.displays.last)
        #expect(xdr.portKey == PortKey(type: 2, number: 1))
        #expect(xdr.modeDescription == "5120 × 2880 @ 120 Hz")
        #expect(xdr.link?.detail == "UHBR13.5 × 4")
        // The Thunderbolt device already stands for the display.
        #expect(!snapshot.allDevices.contains { $0.device.bus == .displayPort })
    }

    @Test func diagnosticsExplainTheFlashDrive() throws {
        #expect(snapshot.diagnostics.map(\.kind) == [.usb2Fallback])
        let finding = try #require(snapshot.diagnostics.first)
        #expect(finding.severity == .warning)
        #expect(finding.title == "DataTraveler 3.0 is running at USB 2 speed")
        #expect(finding.portKey == PortKey(type: 2, number: 2))
        #expect(finding.detail.contains("supports USB 3.0 but is connected at 480 Mb/s on Left Front · USB-C"))
        #expect(DiagnosticsEngine.evaluate(snapshot, raw: DemoScenario.studioDesk.raw(at: S.date)) == snapshot.diagnostics)
    }
}

@Suite("Demo scenarios: travel")
struct DemoTravelTests {
    typealias S = DemoTestSupport
    let snapshot = S.snapshot(.travel)

    @Test func machineAndPorts() {
        #expect(snapshot.machine.model == "Mac16,12")
        #expect(snapshot.machine.name == "MacBook Air (13-inch, M4, 2025)")
        #expect(snapshot.ports.map(\.label.title) == ["Left Rear · MagSafe", "Left Center · USB-C", "Left Front · USB-C"])
        #expect(snapshot.connectedPorts.map(\.key.description) == ["2/1", "2/2"])
        #expect(snapshot.ports.first?.isConnected == false)
        #expect(snapshot.deviceCount == 1)
    }

    @Test func usbCCharger() throws {
        let port = try #require(S.port(snapshot, 2, 1))
        let charger = try #require(port.charger)
        #expect(charger.name == "70W USB-C Power Adapter")
        #expect(charger.ratedWatts == 70)
        #expect(charger.millivolts == 20_000)
        #expect(charger.milliamps == 3_500)
        #expect(charger.portKey == port.key)
        #expect(charger.activeProfile?.label == "20 V × 3.5 A")
        #expect(snapshot.power.charger?.portKey == port.key)
        #expect(port.devices.isEmpty)
        #expect(port.link == nil)

        let power = try #require(port.power)
        #expect(power.direction == .input)
        #expect(power.source == .telemetry)
        #expect(S.isNear(power.milliwatts, 31_200, within: 0.03))

        let battery = try #require(snapshot.power.battery)
        #expect(battery.statusText == "Charging · 82%")
        #expect((battery.powerMilliwatts ?? 0) > 15_000)
    }

    @Test func iPhoneOnAUSB2Cable() throws {
        let port = try #require(S.port(snapshot, 2, 2))
        #expect(port.activeTransports.map(\.kind) == [.usb2])
        #expect(port.link?.label == "USB 2.0 @ 480 Mb/s")
        #expect(port.cable?.speedDescription == "USB 2.0 (480 Mb/s)")
        #expect(port.cable?.currentRatingMilliamps == 5_000)

        let phone = try #require(port.devices.first)
        #expect(port.devices.count == 1)
        #expect(phone.name == "iPhone")
        #expect(phone.kind == .phone)
        #expect(phone.vendorID == 0x05AC)
        #expect(phone.usbVersion == "3.2")
        #expect(phone.link?.label == "USB 2.0 @ 480 Mb/s")

        let power = try #require(port.power)
        #expect(power.direction == .output)
        #expect(power.source == .powerOutDetails)
        #expect(S.isNear(power.milliwatts, 4_500, within: 0.035))
        #expect(power.millivolts == 5_000)
    }

    @Test func diagnosticsExplainTheSlowCable() throws {
        #expect(snapshot.diagnostics.map(\.kind) == [.usb2Fallback])
        let finding = try #require(snapshot.diagnostics.first)
        #expect(finding.title == "iPhone is running at USB 2 speed")
        #expect(finding.detail.contains("supports USB 3.2 but is connected at 480 Mb/s on Left Front · USB-C"))
        #expect(finding.suggestion?.contains("cable") == true)
        #expect(finding.portKey == PortKey(type: 2, number: 2))
    }

    @Test func onlyTheBuiltInDisplay() {
        #expect(snapshot.displays.map(\.name) == ["Built-in Liquid Retina Display"])
        #expect(snapshot.displays.first?.modeDescription == "2560 × 1664 @ 60 Hz")
    }
}

@Suite("Demo scenarios: dock station")
struct DemoDockStationTests {
    typealias S = DemoTestSupport
    let snapshot = S.snapshot(.dockStation)

    @Test func machineAndPortLabels() {
        #expect(snapshot.machine.model == "Mac16,11")
        #expect(snapshot.machine.name == "Mac mini (2024, M4 Pro)")
        #expect(!snapshot.machine.isLaptop)
        #expect(snapshot.ports.map(\.label.title) == [
            "Front (left) · USB-C", "Front (right) · USB-C", "Rear (left) · USB-C", "Rear (center) · USB-C",
            "Rear (right) · USB-C", "Rear · HDMI",
        ])
        #expect(snapshot.connectedPorts.map(\.key.description) == ["2/1", "2/3", "6/1"])
        #expect(S.port(snapshot, 2, 1)?.capabilityDescription == "USB 3 (10 Gb/s)")
        #expect(S.port(snapshot, 2, 3)?.capabilityDescription == "Thunderbolt 5")
        #expect(S.port(snapshot, 2, 1)?.registryName == "Port-USB-C@1")
        #expect(snapshot.deviceCount == 9)
        #expect(snapshot.otherDevices.isEmpty)
    }

    @Test func noBatteryNoCharger() {
        #expect(snapshot.power.battery == nil)
        #expect(snapshot.power.charger == nil)
        #expect(!snapshot.power.hasBattery)
        #expect(snapshot.power.systemInputMilliwatts == nil)
        #expect(snapshot.ports.allSatisfy { $0.charger == nil })
    }

    @Test func thunderbolt5Dock() throws {
        let port = try #require(S.port(snapshot, 2, 3))
        #expect(port.link?.label == "USB4 v2 / TB5 @ 80 Gb/s")
        #expect(port.activeTransports.map(\.kind) == [.cio, .usb2])
        #expect(port.devices.map(\.name) == ["Extreme Pro 55AF", "TS5 Plus"])

        let dock = try #require(port.devices.last)
        #expect(dock.kind == .dock)
        #expect(dock.bus == .thunderbolt)
        #expect(dock.vendorName == "CalDigit, Inc.")
        #expect(dock.link?.label == "USB4 v2 / TB5 @ 80 Gb/s")
        #expect(dock.descendantCount == 5)

        let hub = try #require(dock.children.first)
        #expect(hub.name == "TS5 Plus Hub")
        #expect(hub.power?.isSelfPowered == true)
        #expect(hub.children.map(\.name) == ["Extreme 55AE", "Scarlett 2i2 4th Gen", "SD Card Reader",
                                             "USB 10/100/1G/2.5G LAN"])
        #expect(hub.children.map(\.kind) == [.storage, .audio, .storage, .network])
        #expect(hub.children.map { $0.link?.label ?? "" } == [
            "USB 3.2 Gen 2 @ 10 Gb/s", "USB 2.0 @ 480 Mb/s", "USB 2.0 @ 480 Mb/s", "USB 3.2 Gen 1 @ 5 Gb/s",
        ])

        let fastSSD = try #require(port.devices.first)
        #expect(fastSSD.link?.label == "USB 3.2 Gen 2x2 @ 20 Gb/s")
        #expect(fastSSD.isTunneled)
        #expect(fastSSD.kind == .storage)

        // The dock powers its devices; the SMC measures what the dock draws.
        let power = try #require(port.power)
        #expect(power.source == .smc)
        #expect(S.isNear(power.milliwatts, 1_150, within: 0.04))
    }

    @Test func frontSSDOnABareIOPort() throws {
        let port = try #require(S.port(snapshot, 2, 1))
        #expect(!port.supportsThunderbolt)
        #expect(port.supportedTransports == [.usb3, .usb2])
        #expect(port.link?.label == "USB 3.2 Gen 2 @ 10 Gb/s")
        let ssd = try #require(port.devices.first)
        #expect(ssd.name == "PSSD T7 Shield")
        #expect(ssd.link?.label == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(!ssd.isTunneled)
        // No port controller, no SMC channel: the allocation is the estimate.
        #expect(port.power?.source == .usbAllocation)
        #expect(port.power?.milliwatts == 4_480)
        #expect(snapshot.power.usbAllocatedMilliwatts == 4_480)
        #expect(S.isNear(snapshot.power.portOutputMilliwatts, 4_480 + 1_150, within: 0.01))
    }

    @Test func hdmiDisplay() throws {
        let port = try #require(S.port(snapshot, 6, 1))
        #expect(port.isConnected)
        #expect(port.devices.map(\.name) == ["LG UltraFine"])
        #expect(port.devices.first?.kind == .display)
        let display = try #require(snapshot.displays.first)
        #expect(snapshot.displays.count == 1)
        #expect(display.portKey == port.key)
        #expect(display.modeDescription == "3840 × 2160 @ 60 Hz")
    }

    @Test func noDiagnostics() {
        #expect(snapshot.diagnostics.isEmpty)
    }
}

@Suite("Demo scenarios: unplugged")
struct DemoUnpluggedTests {
    typealias S = DemoTestSupport
    let snapshot = S.snapshot(.unplugged)

    @Test func everyPortEmpty() {
        #expect(snapshot.machine.model == "Mac17,2")
        #expect(snapshot.machine.name == "MacBook Pro (14-inch, 2025, M5)")
        #expect(snapshot.ports.map(\.label.title) == [
            "Left Rear · MagSafe", "Left Center · USB-C", "Left Front · USB-C", "Right Rear · HDMI",
            "Right Center · USB-C",
        ])
        #expect(snapshot.connectedPorts.isEmpty)
        #expect(snapshot.deviceCount == 0)
        #expect(snapshot.ports.allSatisfy { $0.power == nil && $0.cable == nil })
        #expect(snapshot.diagnostics.isEmpty)
    }

    @Test func rightPortIsLabelledByRank() throws {
        // This Mac numbers its USB-C ports 1, 2 and 4; the catalogue lists 1, 2 and 3.
        let port = try #require(S.port(snapshot, 2, 4))
        #expect(port.label.location == "Right Center")
        #expect(port.label.source == .catalogRank)
        #expect(port.supportsThunderbolt)
    }

    @Test func onBattery() throws {
        #expect(snapshot.power.charger == nil)
        let battery = try #require(snapshot.power.battery)
        #expect(battery.percent == 64)
        #expect(!battery.isCharging)
        #expect(!battery.externalConnected)
        #expect(battery.statusText == "On battery · 64%")
        #expect(S.isNear(battery.powerMilliwatts.map { -$0 }, 9_100, within: 0.05))
        #expect(S.isNear(snapshot.power.systemLoadMilliwatts, 9_100, within: 0.05))
        #expect(snapshot.power.portOutputMilliwatts == 0)
        #expect(snapshot.power.headlineMilliwatts == nil)
    }
}
