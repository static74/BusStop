import Foundation
import Testing
@testable import BusStopCore

/// Determinism and crash resistance.
@Suite("Topology: determinism and robustness")
struct TopologyRobustnessTests {
    typealias F = TopologyFixtures

    /// Every fixture used by the other suites, combined into one capture.
    static func everything() -> RawSnapshot {
        var raw = ThunderboltTopologyTests.raw()
        let neo = MacBookNeoFixture.raw()
        raw.portNodes += neo.portNodes.map { node in
            // Move the Neo ports to numbers 5 and 6 so they do not collide.
            var copy = node
            for key in ["PortNumber", "ParentPortNumber", "ParentBuiltInPortNumber"] {
                if let n = copy.properties.int(key) { copy.properties[key] = .int(Int64(n + 4)) }
            }
            for key in ["PortDescription", "Description", "TransportDescription"] {
                if let s = copy.properties.string(key) {
                    copy.properties[key] = .string(s.replacingOccurrences(of: "@1", with: "@5")
                        .replacingOccurrences(of: "@2", with: "@6"))
                }
            }
            return copy
        }
        raw.usbDevices += neo.usbDevices
        raw.battery = neo.battery
        raw.displays = [DisplayTopologyTests.builtIn, DisplayTopologyTests.dell]
        raw.smcChannels = [SMCChannel(index: 2, uuid: "abcd", volts: 5, amps: 1)]
        raw.portControllerUUIDs = ["2/2": "AB-CD"]
        return raw
    }

    @Test func sameInputSameOutput() throws {
        let raw = Self.everything()
        let first = TopologyBuilder.build(raw)
        let second = TopologyBuilder.build(raw)
        #expect(first == second)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        #expect(try encoder.encode(first) == encoder.encode(second))
    }

    @Test func inputOrderDoesNotMatter() {
        let raw = Self.everything()
        var reversed = raw
        reversed.portNodes.reverse()
        reversed.usbDevices.reverse()
        reversed.thunderboltSwitches.reverse()
        reversed.smcChannels.reverse()
        reversed.displays.reverse()
        for i in reversed.thunderboltSwitches.indices { reversed.thunderboltSwitches[i].ports.reverse() }
        var rotated = raw
        rotated.portNodes = Array(raw.portNodes.dropFirst(3) + raw.portNodes.prefix(3))
        rotated.usbDevices = Array(raw.usbDevices.dropFirst(2) + raw.usbDevices.prefix(2))

        let expected = TopologyBuilder.build(raw)
        #expect(TopologyBuilder.build(reversed) == expected)
        #expect(TopologyBuilder.build(rotated) == expected)
    }

    @Test func combinedCaptureIsConsistent() throws {
        let snapshot = TopologyBuilder.build(Self.everything())
        #expect(snapshot.ports.map(\.number) == [1, 2, 3, 5, 6])
        #expect(snapshot.port(PortKey(type: 2, number: 6))?.devices.map(\.name) == ["CT4000X10PROSSD9"])
        #expect(snapshot.power.charger?.portKey == PortKey(type: 2, number: 5))
        let ids = snapshot.allDevices.map(\.device.id)
        #expect(Set(ids).count == ids.count)
        #expect(snapshot.displays.first { !$0.isBuiltin }?.portKey == nil)
    }

    @Test func emptyCapture() {
        let snapshot = TopologyBuilder.build(F.raw())
        #expect(snapshot.ports.isEmpty)
        #expect(snapshot.otherDevices.isEmpty)
        #expect(snapshot.power == PowerSummary(hasBattery: true))
        #expect(snapshot.captureNotes == [TopologyBuilder.noPortDetailNote])
        #expect(snapshot.machine.name == "Mac (Mac99,1)")
    }

    @Test func wrongTypesEverywhere() {
        // Every key the builder reads, with a value of the wrong type.
        let keys = Self.knownKeys
        var bag = PropertyBag()
        for (offset, key) in keys.enumerated() {
            bag[key] = Self.oddValues[offset % Self.oddValues.count]
        }
        let node = RawNode(id: 1, parentID: 1, className: "AppleHPMInterfaceType10", name: "Port-USB-C", properties: bag)
        let transport = RawNode(id: 2, parentID: 1, className: "IOPortTransportStateUSB3", name: "USB3", properties: bag)
        let device = RawUSBDevice(node: RawNode(id: 3, className: "IOUSBHostDevice", name: "", properties: bag),
                                  parentDeviceID: 3, ancestry: [RawAncestor(id: 3, className: "", name: "")],
                                  usbIOPortPath: "", drdPortNumber: -1, ioPortParentID: 2,
                                  interfaces: [RawUSBInterface(interfaceClass: -1, interfaceSubClass: .max,
                                                               interfaceProtocol: .min)])
        let tb = RawThunderboltSwitch(node: RawNode(id: 4, className: "IOThunderboltSwitchType7", name: "", properties: bag),
                                      parentSwitchID: 4, ports: [RawNode(id: 5, className: "IOThunderboltPort",
                                                                         name: "", properties: bag)],
                                      ancestry: [RawAncestor(id: 5, className: "", name: "acio")])
        let raw = F.raw(ports: [node, transport], usb: [device], thunderbolt: [tb], battery: bag, adapter: bag,
                        uuids: ["2/1": "", "x": "y"],
                        smc: [SMCChannel(index: .min, uuid: "", volts: .infinity, amps: .nan)],
                        displays: [RawDisplay(id: .max, name: "", vendorID: .min, productID: .max, serialNumber: .min,
                                              isBuiltin: false, pixelWidth: .min, pixelHeight: .max,
                                              refreshHz: -.infinity)])
        let snapshot = TopologyBuilder.build(raw)
        #expect(snapshot.displays.count == 1)
    }

    @Test func randomCapturesNeverCrash() throws {
        var rng = SplitMix64(seed: 0xB05_5709)
        var portsSeen = 0
        var devicesSeen = 0
        var attributedSeen = 0
        for _ in 0..<400 {
            let raw = Self.randomRaw(&rng)
            let snapshot = TopologyBuilder.build(raw)
            portsSeen += snapshot.ports.count
            devicesSeen += snapshot.deviceCount
            attributedSeen += snapshot.ports.reduce(0) { $0 + $1.deviceCount }
            // Basic invariants hold for any input.
            let keys = snapshot.ports.map(\.key)
            #expect(Set(keys).count == keys.count)
            let ids = snapshot.allDevices.map(\.device.id)
            #expect(Set(ids).count == ids.count)
            #expect(snapshot.ports.allSatisfy { !$0.activeTransports.contains { $0.kind == .cc } })
            #expect(snapshot.ports.allSatisfy { !$0.supportedTransports.contains(.cc) })
            // Compared as JSON: raw property values may hold NaN, which is
            // never equal to itself.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            #expect(try encoder.encode(TopologyBuilder.build(raw)) == encoder.encode(snapshot))
        }
        // The generator must reach the interesting paths, not only empty results.
        #expect(portsSeen > 100)
        #expect(devicesSeen > 100)
        #expect(attributedSeen > 10)
    }

    // MARK: - Random input

    static let knownKeys = [
        "PortTypeDescription", "PortNumber", "PortType", "BuiltIn", "ConnectionActive", "TransportsSupported",
        "TransportsActive", "PortDescription", "Description", "ParentPortType", "ParentPortNumber",
        "ParentBuiltInPortType", "ParentBuiltInPortNumber", "TransportTypeDescription", "TransportDescription",
        "Tunneled", "Active", "DataRate", "DataRateDescription", "SuperSpeedSignaling",
        "SuperSpeedSignalingDescription", "LaneCount", "LinkRate", "LinkRateDescription", "ProductName", "Product",
        "Metadata", "ActiveCable", "OpticalCable", "LDCM_LiquidDetected", "LiquidDetected", "FeatureTypeDescription",
        "ConnectionCount", "Plug Event Count", "Overcurrent Count", "FeaturesEnabled", "WinningPowerSourceOption",
        "PowerSourceName", "User String", "ProtocolName", "Specification Revision", "ComponentName", "VDOs",
        "USB Product Name", "kUSBProductString", "USB Vendor Name", "kUSBVendorString", "USB Serial Number",
        "idVendor", "idProduct", "bcdUSB", "bDeviceClass", "locationID", "UsbLinkSpeed", "Device Speed", "USBSpeed",
        "UsbPowerSinkAllocation", "Requested Power", "kUSBHubPowerSupply", "kUSBHubPowerSupplyType", "UsbTunnel",
        "USBPortType", "Depth", "UID", "Device Vendor Name", "Device Model Name", "Vendor ID", "Device ID",
        "Upstream Port Number", "Socket ID", "Port Number", "Current Link Speed", "Current Link Width",
        "Hop Table", "Link Bandwidth", "AdapterDetails", "PowerTelemetryData", "PowerOutDetails", "ExternalConnected",
        "IsCharging", "FullyCharged", "CurrentCapacity", "MaxCapacity", "NotChargingReason", "BatteryInstalled",
        "ChargerData", "BatteryData", "Watts", "AdapterVoltage", "Current", "Name", "Manufacturer", "FamilyCode",
        "IsWireless", "SerialNumber", "SerialString", "UsbHvcMenu", "UsbHvcHvcIndex", "SystemPowerIn", "SystemLoad",
        "BatteryPower", "PortIndex", "Index", "MaxVoltage", "MaxCurrent", "Voltage", "ConfiguredVoltage",
        "ConfiguredCurrent", "Voltage (mV)", "Max Current (mA)", "Vendor", "Serial Number",
    ]

    static let oddValues: [PlistValue] = [
        .string(""), .string("Yes"), .string("0x1F"), .string("Port-USB-C@2"), .string("Port-USB-C@zz/CIO/USB3"),
        .string("18446744073709549616"), .string("apciec1"), .string("acio1"), .string("xxxxxxxx"),
        .int(.min), .int(.max), .int(0), .int(-1), .int(1), .int(2), .int(3), .int(4), .int(8), .int(9), .int(17),
        .int(1 << 40), .double(.nan), .double(.infinity), .double(-.infinity), .double(1e300), .double(0.5),
        .double(-0.0), .double(18_446_744_073_709_547_520.0), .bool(true), .bool(false), .data(Data()),
        .data(Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F])), .data(Data(repeating: 0x41, count: 12)),
        .date(Date(timeIntervalSince1970: 0)), .array([]), .array([.int(1), .string("CIO"), .dict([:])]),
        .dict([:]), .dict(["Index": .string("x"), "MaxVoltage": .int(.max), "Watts": .double(.nan)]),
    ]

    static let classNames = [
        "AppleHPMInterfaceType10", "IOPort", "AppleHDMIPortController", "IOPortTransportStateCC",
        "IOPortTransportStateUSB2", "IOPortTransportStateUSB3", "IOPortTransportStateDisplayPort",
        "IOPortTransportStateCIO", "IOPortFeaturePowerSource", "IOPortTransportComponentCCUSBPDSOPp",
        "IOPortTransportProtocolAppleUVDM", "AppleHPMLDCMType2", "Mystery",
    ]

    static let ancestorNames = ["apciec0", "apciec1", "acio0", "acio1", "pci-bridge", "usb-auss0", "usb-drd1",
                                "AppleUSBXHCITR", "XHC0", "", "apciec", "acio99999999"]
    static let ancestorClasses = ["AppleUSBXHCITR", "AppleUSBXHCIFL1100", "AppleASMediaUSBXHCI", "AppleUSBXHCIAR",
                                  "AppleT8132USBXHCI", "AppleT6050USBXHCIAUSS", "AppleEmbeddedUSBXHCIFL1100",
                                  "IOThunderboltPort", "IOPCI2PCIBridge", "Other"]

    static func randomValue(_ rng: inout SplitMix64, depth: Int = 0) -> PlistValue {
        switch rng.next(12) {
        case 0, 1, 2, 3: return oddValues[rng.next(oddValues.count)]
        case 4: return .int(Int64(rng.next(20)))
        case 5: return .int(Int64(bitPattern: rng.nextUInt64()))
        case 6: return .double(Double(bitPattern: rng.nextUInt64()))
        case 7: return .string(knownKeys[rng.next(knownKeys.count)])
        case 8: return .data(Data((0..<rng.next(10)).map { _ in UInt8(truncatingIfNeeded: rng.nextUInt64()) }))
        case 9 where depth < 2:
            return .array((0..<rng.next(4)).map { _ in randomValue(&rng, depth: depth + 1) })
        case 10 where depth < 2:
            return .dict(randomBag(&rng, count: rng.next(6), depth: depth + 1).values)
        default: return .bool(rng.next(2) == 0)
        }
    }

    static func randomBag(_ rng: inout SplitMix64, count: Int, depth: Int = 0) -> PropertyBag {
        var bag = PropertyBag()
        for _ in 0..<count { bag[knownKeys[rng.next(knownKeys.count)]] = randomValue(&rng, depth: depth) }
        return bag
    }

    static func randomAncestry(_ rng: inout SplitMix64) -> [RawAncestor] {
        (0..<rng.next(6)).map { _ in
            RawAncestor(id: UInt64(rng.next(40)), className: ancestorClasses[rng.next(ancestorClasses.count)],
                        name: ancestorNames[rng.next(ancestorNames.count)])
        }
    }

    static func randomRaw(_ rng: inout SplitMix64) -> RawSnapshot {
        func id() -> UInt64 { UInt64(rng.next(40)) }
        var nodes: [RawNode] = []
        for _ in 0..<rng.next(14) {
            var bag = randomBag(&rng, count: rng.next(16))
            if rng.next(2) == 0 {
                bag["PortTypeDescription"] = .string(["USB-C", "MagSafe 3", "USB-A", "HDMI", "Inductive"][rng.next(5)])
                bag["PortNumber"] = .int(Int64(rng.next(6)))
            }
            nodes.append(RawNode(id: id(), parentID: rng.next(4) == 0 ? nil : id(),
                                 className: classNames[rng.next(classNames.count)], name: "Node",
                                 location: String(rng.next(9)), properties: bag))
        }
        var usb: [RawUSBDevice] = []
        for _ in 0..<rng.next(10) {
            let node = RawNode(id: id(), className: "IOUSBHostDevice", name: rng.next(3) == 0 ? "" : "Device",
                               properties: randomBag(&rng, count: rng.next(14)))
            usb.append(RawUSBDevice(node: node, parentDeviceID: rng.next(3) == 0 ? nil : id(),
                                    ancestry: randomAncestry(&rng),
                                    usbIOPortPath: rng.next(2) == 0 ? nil : "a/Port-USB-C@\(rng.next(5))",
                                    drdPortNumber: rng.next(2) == 0 ? nil : rng.next(6) - 1,
                                    ioPortParentID: rng.next(2) == 0 ? nil : id(),
                                    interfaces: (0..<rng.next(3)).map { _ in
                                        RawUSBInterface(interfaceClass: rng.next(16), interfaceSubClass: rng.next(14),
                                                        interfaceProtocol: rng.next(3))
                                    }))
        }
        var switches: [RawThunderboltSwitch] = []
        for _ in 0..<rng.next(6) {
            var bag = randomBag(&rng, count: rng.next(8))
            if rng.next(2) == 0 { bag["Depth"] = .int(Int64(rng.next(4))) }
            let ports = (0..<rng.next(4)).map { _ in
                RawNode(id: id(), className: "IOThunderboltPort", name: "Port", properties: randomBag(&rng, count: rng.next(8)))
            }
            switches.append(RawThunderboltSwitch(node: RawNode(id: id(), className: "IOThunderboltSwitchType7",
                                                               name: "Switch", properties: bag),
                                                 parentSwitchID: rng.next(3) == 0 ? nil : id(), ports: ports,
                                                 ancestry: randomAncestry(&rng)))
        }
        let smc = (0..<rng.next(4)).map { i in
            SMCChannel(index: i, uuid: ["aa", "AA-BB", "", "zz"][rng.next(4)],
                       volts: Double(bitPattern: rng.nextUInt64()), amps: rng.next(2) == 0 ? nil : 1.5)
        }
        let displays = (0..<rng.next(3)).map { i in
            RawDisplay(id: UInt32(i), name: rng.next(2) == 0 ? nil : "Display", vendorID: rng.next(3) - 1,
                       productID: nil, serialNumber: rng.next(2) == 0 ? nil : Int(bitPattern: UInt(rng.nextUInt64())),
                       isBuiltin: rng.next(3) == 0, refreshHz: Double(bitPattern: rng.nextUInt64()))
        }
        return RawSnapshot(capturedAt: F.date, machine: F.machine(hasBattery: rng.next(2) == 0), portNodes: nodes,
                           portControllerUUIDs: ["2/1": "aa", "2/2": "AA-BB", "17/1": "zz"], usbDevices: usb,
                           thunderboltSwitches: switches,
                           battery: rng.next(4) == 0 ? nil : randomBag(&rng, count: rng.next(20)),
                           adapter: rng.next(3) == 0 ? nil : randomBag(&rng, count: rng.next(10)),
                           smcChannels: smc, displays: displays)
    }
}

/// A small deterministic generator (SplitMix64) so random tests repeat exactly.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `0..<bound` (bound must be positive).
    mutating func next(_ bound: Int) -> Int {
        Int(nextUInt64() % UInt64(max(bound, 1)))
    }
}
