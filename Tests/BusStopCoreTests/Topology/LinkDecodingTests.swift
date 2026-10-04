import Foundation
import Testing
@testable import BusStopCore

@Suite("Topology: link decoding")
struct LinkDecodingTests {
    // MARK: USB devices

    @Test func usbLinkSpeedWinsOverTheEnums() {
        let link = LinkDecoding.usbDeviceLink(["UsbLinkSpeed": 10_000_000_000, "Device Speed": 2, "USBSpeed": 3])
        #expect(link?.generation == "USB 3.2 Gen 2")
        #expect(link?.bitsPerSecond == 10_000_000_000)
        #expect(link?.label == "USB 3.2 Gen 2 @ 10 Gb/s")
    }

    @Test(arguments: [
        (0, Int64(1_500_000), "USB 1.1 Low Speed"),
        (1, Int64(12_000_000), "USB 1.1 Full Speed"),
        (2, Int64(480_000_000), "USB 2.0"),
        (3, Int64(5_000_000_000), "USB 3.2 Gen 1"),
        (4, Int64(10_000_000_000), "USB 3.2 Gen 2"),
        (5, Int64(20_000_000_000), "USB 3.2 Gen 2x2"),
    ])
    func legacyDeviceSpeedEnum(code: Int, bps: Int64, generation: String) {
        let link = LinkDecoding.usbDeviceLink(["Device Speed": .int(Int64(code))])
        #expect(link?.bitsPerSecond == bps)
        #expect(link?.generation == generation)
    }

    @Test(arguments: [
        (1, Int64(12_000_000)),
        (2, Int64(1_500_000)),
        (3, Int64(480_000_000)),
        (4, Int64(5_000_000_000)),
        (5, Int64(10_000_000_000)),
        (6, Int64(20_000_000_000)),
    ])
    func hostConnectionSpeedEnum(code: Int, bps: Int64) {
        #expect(LinkDecoding.usbDeviceLink(["USBSpeed": .int(Int64(code))])?.bitsPerSecond == bps)
    }

    @Test func enumsAreNeverMixed() {
        // Device Speed 1 is Full speed; USBSpeed 1 is also Full speed, but
        // Device Speed 0 (Low) must not be read through the USBSpeed table.
        #expect(LinkDecoding.usbDeviceLink(["Device Speed": 0, "USBSpeed": 3])?.bitsPerSecond == 1_500_000)
        // An unknown Device Speed falls through to USBSpeed with its own table.
        #expect(LinkDecoding.usbDeviceLink(["Device Speed": 9, "USBSpeed": 2])?.bitsPerSecond == 1_500_000)
        #expect(LinkDecoding.usbDeviceLink(["USBSpeed": 0]) == nil)
        #expect(LinkDecoding.usbDeviceLink(["UsbLinkSpeed": 0]) == nil)
        #expect(LinkDecoding.usbDeviceLink([:]) == nil)
    }

    @Test func realDumpValues() {
        // Micron SSD (macOS 26.3) and Digidesign Mbox (July 2026).
        #expect(LinkDecoding.usbDeviceLink(["UsbLinkSpeed": 480_000_000, "USBSpeed": 3, "Device Speed": 2])?.label
            == "USB 2.0 @ 480 Mb/s")
        #expect(LinkDecoding.usbDeviceLink(["UsbLinkSpeed": 12_000_000, "USBSpeed": 1, "Device Speed": 1])?.label
            == "USB 1.1 Full Speed @ 12 Mb/s")
    }

    // MARK: Transports

    @Test func usb2Transport() {
        #expect(LinkDecoding.usb2TransportLink(["DataRate": 1]).bitsPerSecond == 1_500_000)
        #expect(LinkDecoding.usb2TransportLink(["DataRate": 2]).generation == "USB 1.1 Full Speed")
        #expect(LinkDecoding.usb2TransportLink(["DataRate": 3]).bitsPerSecond == 480_000_000)
        #expect(LinkDecoding.usb2TransportLink(["DataRateDescription": "12 Mbps (Full Speed)"]).bitsPerSecond == 12_000_000)
        #expect(LinkDecoding.usb2TransportLink(nil).label == "USB 2.0 @ 480 Mb/s")
        #expect(LinkDecoding.usb2TransportLink(["DataRateDescription": "480 Mbps (High Speed)", "DataRate": 3]).detail
            == "480 Mbps (High Speed)")
    }

    @Test func usb3Transport() {
        #expect(LinkDecoding.usb3TransportLink(["SuperSpeedSignaling": 1]).label == "USB 3.2 Gen 1 @ 5 Gb/s")
        #expect(LinkDecoding.usb3TransportLink(["SuperSpeedSignaling": 2]).label == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(LinkDecoding.usb3TransportLink(["SuperSpeedSignaling": 2, "SuperSpeedSignalingDescription": "Gen 2x2"])
            .label == "USB 3.2 Gen 2x2 @ 20 Gb/s")
        #expect(LinkDecoding.usb3TransportLink(["SuperSpeedSignaling": 2, "LaneCount": 2]).bitsPerSecond == 20_000_000_000)
        #expect(LinkDecoding.usb3TransportLink(["SuperSpeedSignalingDescription": "Gen 1"]).bitsPerSecond == 5_000_000_000)
        let unknown = LinkDecoding.usb3TransportLink(["GenerationDescription": "USB 3.x"])
        #expect(unknown.generation == "USB 3")
        #expect(unknown.bitsPerSecond == nil)
    }

    @Test func displayPortTransport() {
        let hbr3 = LinkDecoding.displayPortLink(["LinkRateDescription": "8.1 Gbps (HBR3)", "LaneCount": 4])
        #expect(hbr3.family == .displayPort)
        #expect(hbr3.generation == "DisplayPort")
        #expect(hbr3.bitsPerSecond == 32_400_000_000)
        #expect(hbr3.detail == "HBR3 × 4")
        #expect(hbr3.lanes == 4)

        #expect(LinkDecoding.displayPortLink(["LinkRate": 3, "LaneCount": 2]).detail == "HBR2 × 2")
        #expect(LinkDecoding.displayPortLink(["LinkRate": 3, "LaneCount": 2]).bitsPerSecond == 10_800_000_000)
        #expect(LinkDecoding.displayPortLink(["LinkRate": 1, "LaneCount": 4]).bitsPerSecond == 6_480_000_000)
        #expect(LinkDecoding.displayPortLink(["LinkRateDescription": "UHBR13.5", "LaneCount": 4]).bitsPerSecond
            == 54_000_000_000)
        #expect(LinkDecoding.displayPortLink(["LinkRateDescription": "20 Gbps (UHBR20)", "LaneCount": 4]).detail
            == "UHBR20 × 4")
        #expect(LinkDecoding.displayPortLink(["LinkRate": 5, "LaneCount": 1]).detail == "UHBR10 × 1")
        // No link, or a lane count out of range: generation only.
        let idle = LinkDecoding.displayPortLink(["LinkRate": 0, "LaneCount": 9])
        #expect(idle.bitsPerSecond == nil)
        #expect(idle.lanes == nil)
        #expect(idle.label == "DisplayPort")
    }

    // MARK: Thunderbolt

    @Test(arguments: [
        (0x8, 0x2, Int64(20_000_000_000), "Thunderbolt / USB4", 2),
        (0x8, 0x1, Int64(10_000_000_000), "Thunderbolt", 1),
        (0x4, 0x2, Int64(40_000_000_000), "Thunderbolt / USB4", 2),
        (0x4, 0x1, Int64(20_000_000_000), "Thunderbolt / USB4", 1),
        (0x2, 0x2, Int64(80_000_000_000), "USB4 v2 / TB5", 2),
        (0x2, 0x4, Int64(120_000_000_000), "USB4 v2 / TB5", 3),
        (0x2, 0x8, Int64(120_000_000_000), "USB4 v2 / TB5", 3),
    ])
    func thunderboltCodes(speed: Int, width: Int, bps: Int64, generation: String, lanes: Int) {
        let link = LinkDecoding.thunderboltLink(lanePort: ["Current Link Speed": .int(Int64(speed)),
                                                           "Current Link Width": .int(Int64(width))])
        #expect(link?.family == .thunderbolt)
        #expect(link?.bitsPerSecond == bps)
        #expect(link?.generation == generation)
        #expect(link?.lanes == lanes)
        #expect(link?.isAsymmetric == (width & 0xC != 0))
    }

    @Test func thunderboltDetailAndIdle() {
        #expect(LinkDecoding.thunderboltLink(lanePort: ["Current Link Speed": 2, "Current Link Width": 2])?.detail
            == "2 × 40 Gb/s")
        #expect(LinkDecoding.thunderboltLink(lanePort: ["Current Link Speed": 2, "Current Link Width": 4])?.detail
            == "3 × 40 Gb/s one way, 1 × 40 Gb/s the other")
        #expect(LinkDecoding.thunderboltLink(lanePort: ["Current Link Speed": 0, "Current Link Width": 2]) == nil)
        #expect(LinkDecoding.thunderboltLink(lanePort: ["Current Link Speed": 2, "Current Link Width": 0]) == nil)
        // Unknown code: never guessed.
        #expect(LinkDecoding.thunderboltLink(lanePort: ["Current Link Speed": 1, "Current Link Width": 2]) == nil)
        #expect(LinkDecoding.thunderboltLink(lanePort: [:]) == nil)
    }

    // MARK: Helpers

    @Test func parseRate() {
        #expect(LinkDecoding.parseRate("480 Mbps (High Speed)") == 480_000_000)
        #expect(LinkDecoding.parseRate("8.1 Gbps (HBR3)") == 8_100_000_000)
        #expect(LinkDecoding.parseRate("Up to 40 Gb/s x1") == 40_000_000_000)
        #expect(LinkDecoding.parseRate("1.5Mbps") == 1_500_000)
        #expect(LinkDecoding.parseRate("Gen 2") == nil)
        #expect(LinkDecoding.parseRate("") == nil)
        #expect(LinkDecoding.parseRate("1.2.3 Gbps") == nil)
    }

    @Test func faster() {
        let slow = LinkInfo(family: .usb, generation: "USB 2.0", bitsPerSecond: 480_000_000)
        let fast = LinkInfo(family: .usb, generation: "USB 3.2 Gen 2", bitsPerSecond: 10_000_000_000)
        let unknown = LinkInfo(family: .usb, generation: "USB 3")
        #expect(LinkDecoding.faster(slow, fast) == fast)
        #expect(LinkDecoding.faster(fast, slow) == fast)
        #expect(LinkDecoding.faster(unknown, slow) == slow)
        #expect(LinkDecoding.faster(nil, unknown) == unknown)
        #expect(LinkDecoding.faster(nil, nil) == nil)
    }
}

@Suite("Topology: device classifier")
struct DeviceClassifierTests {
    func kind(_ name: String, deviceClass: Int = 0, interfaces: [RawUSBInterface] = [], vendor: Int? = 0x1234)
        -> DeviceKind {
        DeviceClassifier.classify(deviceClass: deviceClass, interfaces: interfaces, name: name, vendorID: vendor)
    }

    @Test func classesComeFirst() {
        #expect(kind("Thing", deviceClass: 9) == .hub)
        #expect(kind("Thing", interfaces: [RawUSBInterface(interfaceClass: 8)]) == .storage)
        #expect(kind("Thing", interfaces: [RawUSBInterface(interfaceClass: 3, interfaceSubClass: 1,
                                                           interfaceProtocol: 1)]) == .keyboard)
        #expect(kind("Thing", interfaces: [RawUSBInterface(interfaceClass: 3, interfaceSubClass: 1,
                                                           interfaceProtocol: 2)]) == .mouse)
        #expect(kind("Thing", interfaces: [RawUSBInterface(interfaceClass: 1)]) == .audio)
        #expect(kind("Thing", interfaces: [RawUSBInterface(interfaceClass: 14), RawUSBInterface(interfaceClass: 1)])
            == .camera)
        #expect(kind("Thing", interfaces: [RawUSBInterface(interfaceClass: 2, interfaceSubClass: 13),
                                           RawUSBInterface(interfaceClass: 10)]) == .network)
        #expect(kind("Thing", interfaces: [RawUSBInterface(interfaceClass: 2, interfaceSubClass: 6)]) == .network)
        #expect(kind("Thing", interfaces: [RawUSBInterface(interfaceClass: 7)]) == .printer)
        #expect(kind("Thing", interfaces: [RawUSBInterface(interfaceClass: 0xE0)]) == .wireless)
        #expect(kind("Thing", interfaces: [RawUSBInterface(interfaceClass: 6)]) == .camera)
        #expect(kind("Thing", interfaces: [RawUSBInterface(interfaceClass: 3)]) == .input)
    }

    @Test func applePhonesAndTablets() {
        let phoneInterfaces = [RawUSBInterface(interfaceClass: 6), RawUSBInterface(interfaceClass: 0xFF),
                               RawUSBInterface(interfaceClass: 2, interfaceSubClass: 13)]
        #expect(kind("iPhone", interfaces: phoneInterfaces, vendor: 0x05AC) == .phone)
        #expect(kind("iPad", interfaces: phoneInterfaces, vendor: 0x05AC) == .tablet)
    }

    @Test func nameKeywordsMatchWholeWords() {
        #expect(kind("USB3.0 Hub") == .hub)
        #expect(kind("Thunderbolt Dock") == .dock)
        #expect(kind("LG UltraFine Display") == .display)
        #expect(kind("SanDisk Extreme SSD") == .storage)
        #expect(kind("SD Card Reader") == .storage)
        #expect(kind("Magic Keyboard with Touch ID") == .keyboard)
        #expect(kind("MX Master Mouse") == .mouse)
        #expect(kind("USB 10/100/1000 LAN") == .network)
        #expect(kind("USB Audio DAC") == .audio)
        #expect(kind("Logitech Webcam C920") == .camera)
        #expect(kind("USB-C to HDMI Adapter") == .adapter)
        // "Microsoft" is not "mic"; "Atlantic" is not "lan".
        #expect(kind("Microsoft Nano Transceiver") == .other)
        #expect(kind("Atlantic Widget") == .other)
    }

    @Test func appleProductNames() {
        #expect(kind("AirPods Pro", vendor: 0x05AC) == .audio)
        #expect(kind("SuperDrive", vendor: 0x05AC) == .storage)
        #expect(kind("AirPods Pro", vendor: 0x1234) == .other)
    }

    @Test func hubWithNetworkChildAndDockNameIsADock() {
        let ethernet = DeviceNode(id: "e", bus: .usb, kind: .network, name: "Ethernet")
        var hub = DeviceNode(id: "h", bus: .usb, kind: .hub, name: "Docking Station Hub", children: [ethernet])
        #expect(DeviceClassifier.refineHub(hub) == .dock)
        hub.name = "USB3.0 Hub"
        #expect(DeviceClassifier.refineHub(hub) == .hub)
        hub.name = "Docking Station Hub"
        hub.children = [DeviceNode(id: "k", bus: .usb, kind: .keyboard, name: "Keyboard")]
        #expect(DeviceClassifier.refineHub(hub) == .hub)
    }
}

@Suite("Topology: text helpers")
struct TopologyTextTests {
    @Test func clean() {
        #expect(TopologyText.clean("  Micron\0") == "Micron")
        #expect(TopologyText.clean("xxxxxxxx") == nil)
        #expect(TopologyText.clean("XXXX") == nil)
        #expect(TopologyText.clean("xx") == "xx")
        #expect(TopologyText.clean("   ") == nil)
        #expect(TopologyText.clean(nil) == nil)
    }

    @Test func nameMatching() {
        #expect(TopologyText.match("Studio Display", "studio  display") == .exact)
        #expect(TopologyText.match("TS5 Plus USB Hub", "TS5 Plus") == .contains)
        #expect(TopologyText.match("TS4 USB Hub", "TS4") == nil)
        #expect(TopologyText.match("Dock", "Display") == nil)
        #expect(TopologyText.match("", "Display") == nil)
    }

    @Test func portComponents() {
        #expect(TopologyText.parsePortComponent("Port-USB-C@2")?.number == 2)
        #expect(TopologyText.parsePortComponent("Port-USB-C@a")?.number == 10)
        #expect(TopologyText.parsePortComponent("Port-MagSafe 3@1")?.typeText == "MagSafe 3")
        #expect(TopologyText.parsePortComponent("Port-USB-C@2\0")?.number == 2)
        #expect(TopologyText.parsePortComponent("AppleHPMDevice@3F") == nil)
        #expect(TopologyText.parsePortComponent("Port-USB-C@") == nil)
        #expect(TopologyText.parsePortComponent("Port-@1") == nil)
        #expect(TopologyText.parsePortComponent("Port-USB-C@zz") == nil)
        #expect(TopologyText.parsePortComponent("Port-USB-C@ffffffffffffffffff") == nil)
        #expect(TopologyText.lastPathComponent("IOService:/AppleARMPE/arm-io/AppleHPMDevice@3F/Port-USB-C@2")
            == "Port-USB-C@2")
        #expect(TopologyText.indexedName("apciec2", prefix: "apciec") == 2)
        #expect(TopologyText.indexedName("apciec", prefix: "apciec") == nil)
        #expect(TopologyText.indexedName("apciec2-x", prefix: "apciec") == nil)
        #expect(TopologyText.hex(UInt64(0x110000), width: 8) == "00110000")
        #expect(TopologyText.hex(0x5ac, width: 4) == "05ac")
    }

    @Test func signedTelemetry() {
        #expect(TopologyValues.signedMilliwatts(.int(-1500)) == -1500)
        #expect(TopologyValues.signedMilliwatts(.int(23987)) == 23987)
        // 2^64 - 4096 as a Double is exact and stands for -4096.
        #expect(TopologyValues.signedMilliwatts(.double(18_446_744_073_709_547_520.0)) == -4096)
        #expect(TopologyValues.signedMilliwatts(.string("18446744073709549616")) == -2000)
        #expect(TopologyValues.signedMilliwatts(.string("-25")) == -25)
        #expect(TopologyValues.signedMilliwatts(.int(Int64.max)) == nil)
        #expect(TopologyValues.signedMilliwatts(.double(6e18)) == nil)
        #expect(TopologyValues.signedMilliwatts(.double(.nan)) == nil)
        #expect(TopologyValues.signedMilliwatts(.double(1e30)) == nil)
        #expect(TopologyValues.signedMilliwatts(.string("hello")) == nil)
        #expect(TopologyValues.signedMilliwatts(.array([])) == nil)
        #expect(TopologyValues.signedMilliwatts(nil) == nil)
    }
}
