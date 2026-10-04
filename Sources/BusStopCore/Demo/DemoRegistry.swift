import Foundation

/// Builds the raw IORegistry records of a demo Mac.
///
/// Every node uses the classes and keys a real Mac publishes, as seen in the
/// macOS 26.3 `IOPort`-plane dump, the iOS 27 dump and the key lists
/// `BusStopKit` reads, so a demo snapshot goes through exactly the same
/// `TopologyBuilder` code path as a live capture. Registry IDs are handed
/// out in call order, so building a scenario twice gives identical records.
struct DemoRegistry {
    /// Registry ID of the `IOPort` plane root, the parent of every port node.
    static let rootID: UInt64 = 0x1_0000_0100

    private var nextID: UInt64
    private(set) var portNodes: [RawNode] = []
    private(set) var usbDevices: [RawUSBDevice] = []
    private(set) var switches: [RawThunderboltSwitch] = []
    /// Port key → HPM controller `UUID` (the SMC join key).
    private(set) var controllerUUIDs: [String: String] = [:]
    /// USB addresses per controller bus, handed out in enumeration order.
    private var usbAddresses: [UInt32: Int] = [:]

    init(firstID: UInt64 = 0x1_0000_0400) {
        nextID = firstID
    }

    /// A fresh registry ID.
    mutating func newID() -> UInt64 {
        let id = nextID
        nextID += 1
        return id
    }

    /// Uppercase hexadecimal, zero-padded to `width` digits, as IOKit
    /// prints registry locations (`"01200000"`).
    static func hexLocation(_ value: UInt64, width: Int = 1) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }
}

// MARK: - Class chains

/// Superclass chains, class first, as `ClassHierarchy` records them.
enum DemoClassChain {
    static func hpm(_ className: String) -> [String] {
        [className, "AppleHPMInterface", "AppleTCController", "IOAccessoryManagerUSBC", "IOAccessoryManager",
         "IOPort", "IOPortFamily", "IOService", "IORegistryEntry"]
    }

    static let barePort = ["IOPort", "IOPortFamily", "IOService", "IORegistryEntry"]
    static let hdmiPort = ["AppleHDMIPortController", "IOPort", "IOPortFamily", "IOService", "IORegistryEntry"]

    static func transport(_ kind: String) -> [String] {
        let usb = kind == "USB2" || kind == "USB3"
        return ["IOPortTransportState\(kind)"] + (usb ? ["IOPortTransportStateUSB"] : [])
            + ["IOPortTransportState", "IOService", "IORegistryEntry"]
    }

    static let ldcm = ["AppleHPMLDCMType2", "AppleHPMLDCM", "IOPortFeatureLDCM", "IOPortFeature", "IOPortFamily",
                       "IOService", "IORegistryEntry"]
    static let powerIn = ["IOPortFeaturePowerIn", "IOPortFeaturePower", "IOPortFeature", "IOPortFamily", "IOService",
                          "IORegistryEntry"]
    static let powerSource = ["IOPortFeaturePowerSource", "IOPortFamily", "IOService", "IORegistryEntry"]

    static func component(_ className: String) -> [String] {
        [className, "IOPortTransportComponentCCUSBPD", "IOPortTransportComponent", "IOService", "IORegistryEntry"]
    }

    static let appleUVDM = ["IOPortTransportProtocolAppleUVDM", "IOPortTransportProtocol", "IOService",
                            "IORegistryEntry"]
    static let usbDevice = ["IOUSBHostDevice", "IOService", "IORegistryEntry"]

    static func thunderboltSwitch(_ className: String) -> [String] {
        [className, "IOThunderboltSwitchOS", "IOThunderboltSwitch", "IOThunderboltNub", "IOService", "IORegistryEntry"]
    }

    static let thunderboltPort = ["IOThunderboltPort", "IOService", "IORegistryEntry"]
}

// MARK: - Ports

/// A physical port node, with what the child builders need to know about it.
struct DemoPortRef {
    let id: UInt64
    /// IOKit `PortType`: 2 USB-C, 17 MagSafe 3, 6 HDMI.
    let type: Int
    let number: Int
    /// `PortTypeDescription`: "USB-C", "MagSafe 3", "HDMI".
    let typeDescription: String
    /// The port's CC transport, parent of its USB-PD components. Ports
    /// without one (bare `IOPort`, HDMI) use their own ID.
    var cc: UInt64

    init(id: UInt64, type: Int, number: Int, typeDescription: String) {
        self.id = id
        self.type = type
        self.number = number
        self.typeDescription = typeDescription
        cc = id
    }

    /// `"Port-USB-C@1"`, with the number in hex as IOKit prints locations.
    var registryName: String { "Port-\(typeDescription)@\(String(number, radix: 16, uppercase: true))" }

    /// The `Parent…` keys every transport, feature and component node carries.
    var parentKeys: [String: PlistValue] {
        [
            "ParentPortType": .int(Int64(type)),
            "ParentPortNumber": .int(Int64(number)),
            "ParentPortTypeDescription": .string(typeDescription),
            "ParentPortBuiltIn": true,
            "ParentBuiltInPortType": .int(Int64(type)),
            "ParentBuiltInPortNumber": .int(Int64(number)),
            "ParentBuiltInPortTypeDescription": .string(typeDescription),
        ]
    }
}

/// What is attached to a port, as the port controller reports it.
struct DemoPortState {
    /// `TransportsSupported`.
    var supported: [String]
    /// `TransportsActive`; empty when nothing is plugged in.
    var active: [String] = []
    /// `FeaturesEnabled`.
    var features: [String] = ["TRM", "LDCM"]
    /// `Plug Event Count` and `ConnectionCount`.
    var plugEvents: Int = 0
    /// `PlugOrientation`: 1 or 2 when something is plugged in.
    var orientation: Int = 1
    var activeCable: Bool = false
    var extra: [String: PlistValue] = [:]

    var isConnected: Bool { !active.isEmpty }
}

extension DemoRegistry {
    /// A USB-C or MagSafe port driven by an HPM controller
    /// (`AppleHPMInterfaceType10` / `Type11`), with its CC transport and LDCM
    /// feature. `uuid` is the parent `AppleHPMDevice` controller's `UUID`.
    @discardableResult
    mutating func hpmPort(number: Int, type: Int = PortKey.usbCType, typeDescription: String = "USB-C",
                          className: String = "AppleHPMInterfaceType10", uuid: String,
                          state: DemoPortState) -> DemoPortRef {
        var port = DemoPortRef(id: newID(), type: type, number: number, typeDescription: typeDescription)
        let connected = state.isConnected
        var p: [String: PlistValue] = [
            "PortTypeDescription": .string(typeDescription),
            "PortType": .int(Int64(type)),
            "PortNumber": .int(Int64(number)),
            "PortDescription": .string(port.registryName),
            "Description": .string(port.registryName),
            "BuiltIn": true,
            "ConnectionActive": .bool(connected),
            "TransportsSupported": .array(state.supported.map(PlistValue.string)),
            "TransportsActive": .array(state.active.map(PlistValue.string)),
            "TransportsProvisioned": .array(state.active.map(PlistValue.string)),
            "FeaturesSupported": .array(featuresSupported(type: type).map(PlistValue.string)),
            "FeaturesEnabled": .array(state.features.map(PlistValue.string)),
            "ActiveCable": .bool(state.activeCable),
            "OpticalCable": false,
            "PlugOrientation": .int(connected ? Int64(state.orientation) : 0),
            "Plug Event Count": .int(Int64(state.plugEvents)),
            "ConnectionCount": .int(Int64(state.plugEvents)),
            "Overcurrent Count": 0,
            "LDCM_LiquidDetected": false,
            "LDCM_StateDescription": "Idle",
            "HPDAsserted": .bool(state.active.contains("DisplayPort")),
            "DisplayPortPinAssignment": 0,
            "AuthorizationRequired": .bool(connected),
            "UserAuthorizationStatusDescription": .string(connected ? "Authorized" : "No Action"),
            "IOAccessoryUSBActive": .bool(state.active.contains("USB2") || state.active.contains("USB3")),
            "IOAccessoryUSBSuperSpeedActive": .bool(state.active.contains("USB3")),
            "IOAccessoryUSBConnectString": .string(connected ? "Host" : "None"),
            "IOAccessoryPowerMode": 3,
            "IOAccessoryActivePowerMode": 1,
            "IOPersonalityPublisher": "com.apple.driver.AppleHPM",
            "IOProviderClass": "AppleHPMDeviceHAL",
        ]
        for (key, value) in state.extra { p[key] = value }
        portNodes.append(RawNode(id: port.id, parentID: Self.rootID, className: className,
                                 classChain: DemoClassChain.hpm(className),
                                 name: "Port-\(typeDescription)", location: String(number, radix: 16, uppercase: true),
                                 properties: PropertyBag(p)))
        controllerUUIDs[PortKey(type: type, number: number).description] = uuid
        port.cc = transport("CC", on: port, parent: port.id, active: connected)
        ldcm(on: port)
        return port
    }

    private func featuresSupported(type: Int) -> [String] {
        type == PortKey.magSafeType ? ["LDCM", "Power In"] : ["TRM", "LDCM", "Power In"]
    }

    /// A port macOS 26+ publishes as a bare `IOPort` (a desktop's front
    /// USB-C ports, which have no HPM controller and no CC transport).
    @discardableResult
    mutating func barePort(number: Int, typeDescription: String = "USB-C", supported: [String],
                           active: [String]) -> DemoPortRef {
        let type = typeDescription == "USB-A" ? PortKey.usbAType : PortKey.usbCType
        let port = DemoPortRef(id: newID(), type: type, number: number, typeDescription: typeDescription)
        var p: [String: PlistValue] = [
            "PortTypeDescription": .string(typeDescription),
            "PortNumber": .int(Int64(number)),
            "PortDescription": .string(port.registryName),
            "Description": .string(port.registryName),
            "BuiltIn": true,
            "ConnectionActive": .bool(!active.isEmpty),
            "TransportsSupported": .array(supported.map(PlistValue.string)),
            "TransportsActive": .array(active.map(PlistValue.string)),
            "IOPersonalityPublisher": "com.apple.iokit.IOAccessoryManager",
        ]
        if typeDescription == "USB-C" { p["PortType"] = .int(Int64(type)) }
        portNodes.append(RawNode(id: port.id, parentID: Self.rootID, className: "IOPort",
                                 classChain: DemoClassChain.barePort, name: "Port-\(typeDescription)",
                                 location: String(number, radix: 16, uppercase: true), properties: PropertyBag(p)))
        return port
    }

    /// The HDMI jack (`AppleHDMIPortController`). `hotPlug` is `HDMI_HPD`.
    @discardableResult
    mutating func hdmiPort(number: Int = 1, hotPlug: Bool) -> DemoPortRef {
        let port = DemoPortRef(id: newID(), type: PortKey.hdmiType, number: number, typeDescription: "HDMI")
        let p: [String: PlistValue] = [
            "PortTypeDescription": "HDMI",
            "PortType": .int(Int64(PortKey.hdmiType)),
            "PortNumber": .int(Int64(number)),
            "PortDescription": .string(port.registryName),
            "Description": .string(port.registryName),
            "BuiltIn": true,
            "ConnectionActive": .bool(hotPlug),
            "HDMI_HPD": .bool(hotPlug),
            "IOPersonalityPublisher": "com.apple.driver.AppleHDMIPortController",
        ]
        portNodes.append(RawNode(id: port.id, parentID: Self.rootID, className: "AppleHDMIPortController",
                                 classChain: DemoClassChain.hdmiPort, name: "Port-HDMI",
                                 location: String(number, radix: 16, uppercase: true), properties: PropertyBag(p)))
        return port
    }
}

// MARK: - Transports, features and PD components

extension DemoRegistry {
    /// An `IOPortTransportState*` node. `parent` is the port, or the CIO
    /// transport for a tunnelled transport (`path` then reads like
    /// `"Port-USB-C@1/CIO/USB3@0"`).
    @discardableResult
    mutating func transport(_ kind: String, on port: DemoPortRef, parent: UInt64, active: Bool,
                            tunneled: Bool = false, extra: [String: PlistValue] = [:]) -> UInt64 {
        let id = newID()
        let path = tunneled ? "\(port.registryName)/CIO/\(kind)@0" : "\(port.registryName)/\(kind)"
        let typeCodes = ["CC": 1, "USB2": 2, "USB3": 3, "DisplayPort": 4, "CIO": 5]
        var p = port.parentKeys
        p["TransportTypeDescription"] = .string(kind)
        p["TransportType"] = .int(Int64(typeCodes[kind] ?? 0))
        p["TransportDescription"] = .string(path)
        p["Tunneled"] = .bool(tunneled)
        p["Active"] = .bool(active)
        p["Index"] = 0
        p["Metadata"] = .dict([:])
        if kind != "CC" {
            p["AuthorizationRequired"] = true
            p["AuthorizationStatusDescription"] = .string(active ? "Policy Authorized" : "Not Required")
            p["DriverStatusDescription"] = .string(active ? "Ready" : "Not Monitored")
            p["TRM_StateDescription"] = "Unrestricted"
            p["TRM_TransportRestricted"] = false
        }
        for (key, value) in extra { p[key] = value }
        portNodes.append(RawNode(id: id, parentID: parent, className: "IOPortTransportState\(kind)",
                                 classChain: DemoClassChain.transport(kind), name: tunneled ? "\(kind)@0" : kind,
                                 location: tunneled ? "0" : nil, properties: PropertyBag(p)))
        return id
    }

    /// `IOPortTransportStateUSB2` keys for a high-speed link to `product`.
    static func usb2Keys(product: String?, manufacturer: String?, vendorID: Int?, productID: Int?,
                         serial: String? = nil, deviceClass: Int = 0) -> [String: PlistValue] {
        var p: [String: PlistValue] = [
            "DataRate": 3,
            "DataRateDescription": "480 Mbps (High Speed)",
            "Generation": 1,
            "GenerationDescription": "USB 2.0",
            "DataRole": 2,
            "DataRoleDescription": "Host",
        ]
        var metadata: [String: PlistValue] = ["Device Class": .int(Int64(deviceClass))]
        if let product {
            p["Product"] = .string(product)
            metadata["Product"] = .string(product)
        }
        if let manufacturer {
            p["Manufacturer"] = .string(manufacturer)
            metadata["Manufacturer"] = .string(manufacturer)
        }
        if let vendorID {
            p["Vendor ID"] = .int(Int64(vendorID))
            metadata["Vendor ID"] = .int(Int64(vendorID))
        }
        if let productID {
            p["Product ID"] = .int(Int64(productID))
            metadata["Product ID"] = .int(Int64(productID))
        }
        if let serial {
            p["Serial Number"] = .string(serial)
            metadata["Serial Number"] = .string(serial)
        }
        p["Metadata"] = .dict(metadata)
        return p
    }

    /// `IOPortTransportStateUSB3` keys: `generation` 1 is 5 Gb/s, 2 is 10 Gb/s.
    static func usb3Keys(generation: Int) -> [String: PlistValue] {
        [
            "SuperSpeedSignaling": .int(Int64(generation)),
            "SuperSpeedSignalingDescription": .string("Gen \(generation)"),
            "Generation": 2,
            "GenerationDescription": "USB 3.x",
            "DataRate": 0,
            "DataRateDescription": "None",
            "DataRole": 2,
            "DataRoleDescription": "Host",
        ]
    }

    /// `IOPortTransportStateDisplayPort` keys for a link to a named sink.
    static func displayPortKeys(rate: String, rateCode: Int, lanes: Int, product: String,
                                manufacturer: String) -> [String: PlistValue] {
        [
            "LinkRate": .int(Int64(rateCode)),
            "LinkRateDescription": .string(rate),
            "LaneCount": .int(Int64(lanes)),
            "MaxLaneCount": 4,
            "HPD_State": 1,
            "HPD_StateDescription": "High",
            "ProductName": .string(product),
            "ManufacturerName": .string(manufacturer),
            "SinkCount": 1,
        ]
    }

    /// The liquid-detection feature every HPM port carries.
    private mutating func ldcm(on port: DemoPortRef) {
        var p = port.parentKeys
        p["FeatureTypeDescription"] = "LDCM"
        p["FeatureType"] = 2
        p["LiquidDetected"] = false
        p["StateDescription"] = "Hardware Controlled"
        p["MeasurementStatusDescription"] = "No Error"
        p["MitigationsEnabled"] = false
        p["Description"] = .string("\(port.registryName)/LDCM")
        portNodes.append(RawNode(id: newID(), parentID: port.id, className: "AppleHPMLDCMType2",
                                 classChain: DemoClassChain.ldcm, name: "LDCM", properties: PropertyBag(p)))
    }

    /// One fixed power option of an `IOPortFeaturePowerSource`.
    static func powerOption(millivolts: Int, milliamps: Int, uuid: String) -> PlistValue {
        .dict([
            "Voltage (mV)": .int(Int64(millivolts)),
            "Max Current (mA)": .int(Int64(milliamps)),
            "Max Power (mW)": .int(Int64(millivolts * milliamps / 1000)),
            "UUID": .string(uuid),
            "Class": "IOPortFeaturePowerSourceOptionFixed",
        ])
    }

    /// The "Power In" feature with its power sources, each listing its
    /// options lowest first. The source named in `winner` gets `[*]` in its
    /// name and its last (highest) option as `WinningPowerSourceOption`, as
    /// macOS marks the source the Mac charges from.
    mutating func powerIn(on port: DemoPortRef, sources: [(name: String, options: [PlistValue])], winner: String?) {
        let featureID = newID()
        var p = port.parentKeys
        p["FeatureTypeDescription"] = "Power In"
        p["FeatureType"] = 3
        p["Active"] = .bool(winner != nil)
        p["Description"] = .string("\(port.registryName)/Power In")
        p["Metadata"] = .dict([:])
        portNodes.append(RawNode(id: featureID, parentID: port.id, className: "IOPortFeaturePowerIn",
                                 classChain: DemoClassChain.powerIn, name: "Power In", properties: PropertyBag(p)))
        for (offset, source) in sources.enumerated() {
            var s = port.parentKeys
            s["PowerSourceName"] = .string(source.name)
            s["PowerSourceType"] = 0
            s["PowerSourceOptions"] = .array(source.options)
            s["ParentFeatureType"] = 3
            s["Priority"] = .int(Int64(sources.count - offset))
            s["Description"] = .string("\(port.registryName)/Power In/\(source.name)")
            s["Metadata"] = .dict([:])
            let isWinner = source.name == winner
            if isWinner, let option = source.options.last { s["WinningPowerSourceOption"] = option }
            portNodes.append(RawNode(id: newID(), parentID: featureID, className: "IOPortFeaturePowerSource",
                                     classChain: DemoClassChain.powerSource,
                                     name: isWinner ? "\(source.name) [*]" : source.name, properties: PropertyBag(s)))
        }
    }

    /// The USB-PD port partner (`SOP`) under the CC transport.
    @discardableResult
    mutating func partner(on port: DemoPortRef, revision: Int = 3) -> UInt64 {
        let id = newID()
        var p = port.parentKeys
        p["ComponentName"] = "SOP"
        p["AddressDescription"] = "SOP"
        p["Address"] = 1
        p["Specification Revision"] = .int(Int64(revision))
        p["Description"] = .string("\(port.registryName)/CC/SOP")
        p["ParentTransportType"] = 1
        p["ParentTransportTypeDescription"] = .string("\(port.registryName)/CC")
        p["Metadata"] = .dict([:])
        portNodes.append(RawNode(id: id, parentID: port.cc, className: "IOPortTransportComponentCCUSBPDSOP",
                                 classChain: DemoClassChain.component("IOPortTransportComponentCCUSBPDSOP"),
                                 name: "SOP", properties: PropertyBag(p)))
        return id
    }

    /// The cable's e-marker (`SOP'`) with its Discover Identity VDOs, stored
    /// as 4-byte little-endian `Data` the way IOKit publishes them.
    mutating func cableMarker(on port: DemoPortRef, typeDescription: String, vdos: [UInt32]) {
        var p = port.parentKeys
        p["ComponentName"] = "SOP'"
        p["AddressDescription"] = "SOP'"
        p["Address"] = 2
        p["Specification Revision"] = 3
        p["Description"] = .string("\(port.registryName)/CC/SOP'")
        p["ParentTransportType"] = 1
        p["ParentTransportTypeDescription"] = .string("\(port.registryName)/CC")
        p["Metadata"] = .dict([
            "Product Type Description": .string(typeDescription),
            "VDOs": .array(vdos.map { vdo in
                .data(Data([UInt8(vdo & 0xFF), UInt8((vdo >> 8) & 0xFF), UInt8((vdo >> 16) & 0xFF),
                            UInt8((vdo >> 24) & 0xFF)]))
            }),
        ])
        portNodes.append(RawNode(id: newID(), parentID: port.cc, className: "IOPortTransportComponentCCUSBPDSOPp",
                                 classChain: DemoClassChain.component("IOPortTransportComponentCCUSBPDSOPp"),
                                 name: "SOP'", properties: PropertyBag(p)))
    }

    /// An Apple charger identifying itself over Apple VDMs, under `SOP`.
    mutating func appleCharger(on port: DemoPortRef, sop: UInt64, name: String, model: String, serial: String) {
        var p = port.parentKeys
        p["ProtocolName"] = "AppleUVDM"
        p["User String"] = .string(name)
        p["Vendor"] = "Apple Inc."
        p["Manufacturer"] = "0x05AC"
        p["Model"] = .string(model)
        p["Serial Number"] = .string(serial)
        p["Hardware Version"] = "1.0"
        p["Firmware Version"] = "01070052"
        p["ParentComponentName"] = "SOP"
        p["ParentComponentDescription"] = .string("\(port.registryName)/CC/SOP")
        p["Description"] = .string("\(port.registryName)/CC/SOP/AppleUVDM")
        portNodes.append(RawNode(id: newID(), parentID: sop, className: "IOPortTransportProtocolAppleUVDM",
                                 classChain: DemoClassChain.appleUVDM, name: "AppleUVDM", properties: PropertyBag(p)))
    }
}

// MARK: - Cable e-markers

/// USB PD Discover Identity VDOs for e-marked cables.
enum DemoCableVDO {
    /// ID header for a passive cable from `vendorID`.
    static func passiveHeader(vendorID: Int) -> UInt32 {
        (3 << 27) | UInt32(vendorID & 0xFFFF)
    }

    /// Product VDO: product ID in the high half, `bcdDevice` in the low half.
    static func product(productID: Int, bcdDevice: Int = 0x0100) -> UInt32 {
        (UInt32(productID & 0xFFFF) << 16) | UInt32(bcdDevice & 0xFFFF)
    }

    /// Passive cable VDO: USB Type-C plug, 50 V EPR rating, `speed` (0 USB 2,
    /// 1 Gen 1, 2 Gen 2, 3 USB4 Gen 3, 4 USB4 Gen 4), 5 A when `fiveAmps`.
    static func passiveCable(speed: UInt32, fiveAmps: Bool, latency: UInt32) -> UInt32 {
        let hardwareVersion: UInt32 = 1 << 28
        let typeCPlug: UInt32 = 0b10 << 18
        let eprCapable: UInt32 = 1 << 17
        let maxVoltage50V: UInt32 = 0b11 << 9
        let current: UInt32 = (fiveAmps ? 0b10 : 0b01) << 5
        return hardwareVersion | typeCPlug | eprCapable | ((latency & 0xF) << 13) | maxVoltage50V | current
            | (speed & 0b111)
    }
}

// MARK: - USB

/// Descriptor-level facts about one USB device.
struct DemoUSBDevice {
    var name: String
    var vendorName: String?
    var vendorID: Int
    var productID: Int
    var bcdDevice: Int = 0x0100
    var bcdUSB: Int
    var deviceClass: Int = 0
    /// Negotiated link in bits per second (`UsbLinkSpeed`).
    var speed: Int64
    /// `UsbPowerSinkAllocation` in mA at 5 V.
    var allocation: Int?
    var serial: String?
    var interfaces: [RawUSBInterface] = []
    /// `kUSBHubPowerSupply` for hubs: mA the hub supplies downstream, 0 when
    /// it is bus-powered.
    var hubPowerSupply: Int?
    /// Reached through a USB4 tunnel (`UsbTunnel`).
    var isTunneled = false

    var isHub: Bool { deviceClass == 9 }
}

/// A USB host controller and the registry path down to its root ports.
struct DemoUSBController {
    /// Top byte of every `locationID` on this controller.
    let bus: UInt32
    /// Root-port wrappers (high-speed, SuperSpeed), the controller and
    /// everything above it, nearest first, without the root port.
    let ancestry: [RawAncestor]
    let highSpeedPort: RawAncestor
    let superSpeedPort: RawAncestor
    /// `UsbIOPort` path to the physical port, when the controller has one.
    let portPath: String?
    /// `port-number` of the `usb-drdN` ancestor.
    let drdPortNumber: Int?
}

/// A placed USB device, as children need it.
struct DemoUSBRef {
    let id: UInt64
    let location: UInt32
    /// Hub tiers between the root port and this device (0 on a root port).
    let tier: Int
    let isSuperSpeed: Bool
    let name: String
    let ancestry: [RawAncestor]
    let controller: DemoUSBController
}

extension DemoRegistry {
    /// The SoC's own xHCI behind `usb-drdN`, serving the USB-C port `port`
    /// (`soc` is the chip's code, e.g. `"T6050"`). `hpm` numbers the port's
    /// HPM controller in the `UsbIOPort` path; nil for a bare `IOPort`,
    /// which hangs below the controller itself.
    mutating func nativeController(drd: Int, soc: String, port: DemoPortRef?, hpm: Int?) -> DemoUSBController {
        let bus = UInt64(drd)
        let drdNode = RawAncestor(id: newID(), className: "AppleARMIODevice", name: "usb-drd\(drd)",
                                  location: Self.hexLocation(0x8228_0000 + bus * 0x0400_0000))
        let controller = RawAncestor(id: newID(), className: "Apple\(soc)USBXHCI", name: "Apple\(soc)USBXHCI",
                                     location: "00000000")
        let hs = RawAncestor(id: newID(), className: "AppleUSB20XHCITypeCPort", name: "usb-drd\(drd)-port-hs",
                             location: Self.hexLocation(bus << 24 | 0x10_0000, width: 8))
        let ss = RawAncestor(id: newID(), className: "AppleUSB30XHCITypeCPort", name: "usb-drd\(drd)-port-ss",
                             location: Self.hexLocation(bus << 24 | 0x20_0000, width: 8))
        let above = [controller, drdNode,
                     RawAncestor(id: newID(), className: "Apple\(soc)IO", name: "Apple\(soc)IO"),
                     RawAncestor(id: newID(), className: "AppleARMIODevice", name: "arm-io", location: "10F00000")]
        let path = port.map { port -> String in
            let base = "IOService:/AppleARMPE/arm-io@10F00000/Apple\(soc)IO/"
            guard let hpm else { return base + "usb-drd\(drd)@\(drdNode.location ?? "0")/\(port.registryName)" }
            return base + "hpm\(hpm)@38/AppleHPMARM/AppleHPMDeviceHALType3@38/\(port.registryName)"
        }
        return DemoUSBController(bus: UInt32(drd), ancestry: above, highSpeedPort: hs, superSpeedPort: ss,
                                 portPath: path, drdPortNumber: port?.number)
    }

    /// A USB controller inside a dock (`className`, e.g. an ASMedia xHCI),
    /// reached over a PCIe tunnel through `apciecN`.
    mutating func pcieController(className: String, soc: String, bus: UInt32, pcie: Int) -> DemoUSBController {
        let wide = UInt64(bus)
        let controller = RawAncestor(id: newID(), className: className, name: className, location: "00000000")
        let above = [controller,
                     RawAncestor(id: newID(), className: "IOPCIDevice", name: "pci1b21,3242", location: "0"),
                     RawAncestor(id: newID(), className: "IOPCI2PCIBridge", name: "pci-bridge", location: "2"),
                     RawAncestor(id: newID(), className: "IOPCIDevice", name: "pci-bridge", location: "0"),
                     RawAncestor(id: newID(), className: "IOPCI2PCIBridge", name: "pci-bridge", location: "0"),
                     RawAncestor(id: newID(), className: "Apple\(soc)PCIeC", name: "apciec\(pcie)",
                                 location: Self.hexLocation(0x9_0000_0000 + UInt64(pcie) * 0x0100_0000))]
        let hs = RawAncestor(id: newID(), className: "AppleUSB20XHCIPort", name: "HS01",
                             location: Self.hexLocation(wide << 24 | 0x10_0000, width: 8))
        let ss = RawAncestor(id: newID(), className: "AppleUSB30XHCIPort", name: "SS01",
                             location: Self.hexLocation(wide << 24 | 0x20_0000, width: 8))
        return DemoUSBController(bus: bus, ancestry: above, highSpeedPort: hs, superSpeedPort: ss, portPath: nil,
                                 drdPortNumber: nil)
    }

    /// A device on one of the controller's root ports. SuperSpeed devices go
    /// on the SuperSpeed root port, everything else on the high-speed one.
    /// `transport` is its `IOPort`-plane parent (a USB2 or USB3 transport).
    @discardableResult
    mutating func usbRoot(_ device: DemoUSBDevice, on controller: DemoUSBController,
                          transport: UInt64?) -> DemoUSBRef {
        let superSpeed = device.speed > LinkDecoding.highSpeed
        let rootPort: UInt32 = superSpeed ? 2 : 1
        let location = (controller.bus << 24) | (rootPort << 20)
        let ancestry = [superSpeed ? controller.superSpeedPort : controller.highSpeedPort] + controller.ancestry
        return addUSB(device, location: location, tier: 0, parent: nil, ancestry: ancestry, controller: controller,
                      ioPortParent: transport)
    }

    /// A device on port `hubPort` of `hub`.
    @discardableResult
    mutating func usbChild(_ device: DemoUSBDevice, of hub: DemoUSBRef, hubPort: Int) -> DemoUSBRef {
        let shift = UInt32(16 - 4 * hub.tier)
        let location = hub.location | (UInt32(hubPort & 0xF) << shift)
        let portClass = hub.isSuperSpeed ? "AppleUSB30HubPort" : "AppleUSB20HubPort"
        let hubDriver = hub.isSuperSpeed ? "AppleUSB30Hub" : "AppleUSB20Hub"
        let ancestry = [RawAncestor(id: newID(), className: portClass, name: portClass,
                                    location: Self.hexLocation(UInt64(location), width: 8)),
                        RawAncestor(id: newID(), className: hubDriver, name: hubDriver,
                                    location: Self.hexLocation(UInt64(hub.location), width: 8)),
                        RawAncestor(id: hub.id, className: "IOUSBHostDevice", name: hub.name,
                                    location: Self.hexLocation(UInt64(hub.location), width: 8))] + hub.ancestry
        return addUSB(device, location: location, tier: hub.tier + 1, parent: hub.id, ancestry: ancestry,
                      controller: hub.controller, ioPortParent: nil)
    }

    private mutating func addUSB(_ device: DemoUSBDevice, location: UInt32, tier: Int, parent: UInt64?,
                                 ancestry: [RawAncestor], controller: DemoUSBController,
                                 ioPortParent: UInt64?) -> DemoUSBRef {
        let id = newID()
        let address = (usbAddresses[controller.bus] ?? 1) + 1
        usbAddresses[controller.bus] = address
        var p: [String: PlistValue] = [
            "USB Product Name": .string(device.name),
            "kUSBProductString": .string(device.name),
            "idVendor": .int(Int64(device.vendorID)),
            "idProduct": .int(Int64(device.productID)),
            "bcdDevice": .int(Int64(device.bcdDevice)),
            "bcdUSB": .int(Int64(device.bcdUSB)),
            "bDeviceClass": .int(Int64(device.deviceClass)),
            "bDeviceSubClass": 0,
            "bDeviceProtocol": .int(device.isHub ? (device.speed > LinkDecoding.highSpeed ? 3 : 1) : 0),
            "bMaxPacketSize0": .int(device.speed > LinkDecoding.highSpeed ? 9 : (device.speed > 12_000_000 ? 64 : 8)),
            "bNumConfigurations": 1,
            "kUSBCurrentConfiguration": 1,
            "locationID": .int(Int64(location)),
            "USB Address": .int(Int64(address)),
            "kUSBAddress": .int(Int64(address)),
            "UsbLinkSpeed": .int(device.speed),
            "USBPortType": 5,
            "Usb3LinkPreferred": .bool(device.bcdUSB >= 0x0300),
        ]
        if let code = Self.legacySpeedCode(device.speed) { p["Device Speed"] = .int(Int64(code)) }
        if let code = Self.hostSpeedCode(device.speed) { p["USBSpeed"] = .int(Int64(code)) }
        if let vendor = device.vendorName {
            p["USB Vendor Name"] = .string(vendor)
            p["kUSBVendorString"] = .string(vendor)
        }
        if let serial = device.serial {
            p["USB Serial Number"] = .string(serial)
            p["kUSBSerialNumberString"] = .string(serial)
        }
        if let allocation = device.allocation { p["UsbPowerSinkAllocation"] = .int(Int64(allocation)) }
        if let supply = device.hubPowerSupply { p["kUSBHubPowerSupply"] = .int(Int64(supply)) }
        if device.isTunneled { p["UsbTunnel"] = true }

        let node = RawNode(id: id, className: "IOUSBHostDevice", classChain: DemoClassChain.usbDevice,
                           name: device.name, location: Self.hexLocation(UInt64(location), width: 8),
                           properties: PropertyBag(p))
        usbDevices.append(RawUSBDevice(node: node, parentDeviceID: parent, ancestry: ancestry,
                                       usbIOPortPath: controller.portPath, drdPortNumber: controller.drdPortNumber,
                                       ioPortParentID: ioPortParent, interfaces: device.interfaces))
        return DemoUSBRef(id: id, location: location, tier: tier, isSuperSpeed: device.speed > LinkDecoding.highSpeed,
                          name: device.name, ancestry: ancestry, controller: controller)
    }

    /// The legacy `Device Speed` enum: 0 low, 1 full, 2 high, 3 5G, 4 10G, 5 20G.
    static func legacySpeedCode(_ bps: Int64) -> Int? {
        switch bps {
        case LinkDecoding.lowSpeed: return 0
        case LinkDecoding.fullSpeed: return 1
        case LinkDecoding.highSpeed: return 2
        case LinkDecoding.superSpeed: return 3
        case LinkDecoding.superSpeedPlus: return 4
        case LinkDecoding.superSpeedPlus2x2: return 5
        default: return nil
        }
    }

    /// `USBSpeed` (`tIOUSBHostConnectionSpeed`): 1 full, 2 low, 3 high,
    /// 4 super, 5 super+, 6 super+ 2x2.
    static func hostSpeedCode(_ bps: Int64) -> Int? {
        switch bps {
        case LinkDecoding.fullSpeed: return 1
        case LinkDecoding.lowSpeed: return 2
        case LinkDecoding.highSpeed: return 3
        case LinkDecoding.superSpeed: return 4
        case LinkDecoding.superSpeedPlus: return 5
        case LinkDecoding.superSpeedPlus2x2: return 6
        default: return nil
        }
    }
}

// MARK: - Thunderbolt

/// A trained Thunderbolt / USB4 link on a lane adapter.
struct DemoThunderboltLink {
    /// `Current Link Speed`: 0x8 = 10, 0x4 = 20, 0x2 = 40 Gb/s per lane.
    var speedCode: Int
    /// `Current Link Width`: 0x1 one lane, 0x2 two lanes.
    var widthCode: Int
    /// `Supported Link Speed` mask (14 = up to 40 Gb/s per lane).
    var supportedMask: Int = 0xE

    /// `Link Bandwidth`, in units of 100 Mb/s.
    var bandwidth: Int {
        let perLane = LinkDecoding.thunderboltPerLaneGbps(speedCode: speedCode) ?? 0
        let lanes = LinkDecoding.thunderboltWidth(code: widthCode)?.lanes ?? 0
        return perLane * lanes * 10
    }

    /// Two lanes at 40 Gb/s: USB4 v2 / Thunderbolt 5.
    static let tb5 = DemoThunderboltLink(speedCode: 0x2, widthCode: 0x2)
}

/// A protocol adapter on a switch (`"DP or HDMI Adapter"`, `"PCIe Adapter"`, …).
struct DemoThunderboltAdapter {
    var portNumber: Int
    var description: String
    /// A tunnel runs through it (non-empty `Hop Table`).
    var isLive: Bool
}

/// A switch as later builders need it.
struct DemoSwitchRef {
    let id: UInt64
    let className: String
    /// Lane adapters by `Port Number`.
    let lanes: [Int: UInt64]
    let ancestry: [RawAncestor]
}

extension DemoRegistry {
    /// The Mac's own switch for one USB-C port, under `acioN`. Its two lane
    /// adapters carry `Socket ID` = the port number. `type` is the
    /// controller generation (7 on M4 Pro, M4 Max and M5, whose idle lanes
    /// read speed 0 and width 0; 5 on earlier chips, whose idle lanes read
    /// 10 Gb/s on one lane, passed as `idleLink`).
    @discardableResult
    mutating func hostSwitch(acio: Int, socket: Int, uid: Int64, modelName: String, type: Int = 7,
                             link: DemoThunderboltLink?, idleLink: DemoThunderboltLink? = nil,
                             adapters: [DemoThunderboltAdapter] = []) -> DemoSwitchRef {
        let className = "IOThunderboltSwitchType\(type)"
        let ancestry = [
            RawAncestor(id: newID(), className: "IOThunderboltControllerType\(type)",
                        name: "IOThunderboltControllerType\(type)"),
            RawAncestor(id: newID(), className: "AppleThunderboltNHIType\(type)", name: "AppleThunderboltNHIType\(type)"),
            RawAncestor(id: newID(), className: "AppleThunderboltHALType\(type)", name: "AppleThunderboltHALType\(type)"),
            RawAncestor(id: newID(), className: "AppleARMIODevice", name: "acio\(acio)",
                        location: Self.hexLocation(0x0A00_0000 + UInt64(acio) * 0x0400_0000)),
        ]
        let id = newID()
        var ports: [RawNode] = []
        var lanes: [Int: UInt64] = [:]
        for lane in [1, 2] {
            let laneID = newID()
            lanes[lane] = laneID
            var p = Self.laneKeys(portNumber: lane, link: link ?? idleLink)
            if link == nil, idleLink != nil { p["Hop Table"] = .array([]) }
            p["Socket ID"] = .string(String(socket))
            ports.append(RawNode(id: laneID, parentID: id, className: "IOThunderboltPort",
                                 classChain: DemoClassChain.thunderboltPort, name: "IOThunderboltPort",
                                 location: String(lane), properties: PropertyBag(p)))
        }
        let standard = [DemoThunderboltAdapter(portNumber: 0, description: "Thunderbolt Native Host Interface Adapter",
                                               isLive: true)]
        ports += (standard + adapters).map { adapter in adapterNode(adapter, switchID: id) }
        let properties: [String: PlistValue] = [
            "Depth": 0,
            "Route String": 0,
            "UID": .int(uid),
            "Vendor ID": 1452,
            "Device Vendor Name": "Apple Inc.",
            "Device Model Name": .string(modelName),
            "Thunderbolt Version": .int(type >= 7 ? 64 : 32),
            "Upstream Port Number": 0,
            "Max Port Number": 15,
            "Supported Link Speed": .int(Int64((link ?? idleLink)?.supportedMask ?? 0xE)),
        ]
        switches.append(RawThunderboltSwitch(
            node: RawNode(id: id, className: className, classChain: DemoClassChain.thunderboltSwitch(className),
                          name: className, location: "0", properties: PropertyBag(properties)),
            ports: ports, ancestry: ancestry))
        return DemoSwitchRef(id: id, className: className, lanes: lanes, ancestry: ancestry)
    }

    /// A device's switch, `depth` hops from the Mac, cabled to `parentLane`
    /// of `parent`. Its upstream lanes are ports 1 and 2.
    @discardableResult
    mutating func deviceSwitch(below parent: DemoSwitchRef, parentLane: Int, depth: Int, uid: Int64,
                               className: String, vendorID: Int, vendorName: String, deviceID: Int, modelName: String,
                               link: DemoThunderboltLink, downstreamLanes: [Int] = [],
                               adapters: [DemoThunderboltAdapter]) -> DemoSwitchRef {
        let id = newID()
        let laneAncestor = RawAncestor(id: parent.lanes[parentLane] ?? 0, className: "IOThunderboltPort",
                                       name: "IOThunderboltPort", location: String(parentLane))
        let ancestry = [laneAncestor, RawAncestor(id: parent.id, className: parent.className, name: parent.className)]
            + parent.ancestry
        var ports: [RawNode] = []
        var lanes: [Int: UInt64] = [:]
        for lane in [1, 2] + downstreamLanes {
            let laneID = newID()
            lanes[lane] = laneID
            let upstream = lane <= 2
            ports.append(RawNode(id: laneID, parentID: id, className: "IOThunderboltPort",
                                 classChain: DemoClassChain.thunderboltPort, name: "IOThunderboltPort",
                                 location: String(lane),
                                 properties: PropertyBag(Self.laneKeys(portNumber: lane, link: upstream ? link : nil))))
        }
        ports += adapters.map { adapterNode($0, switchID: id) }
        let properties: [String: PlistValue] = [
            "Depth": .int(Int64(depth)),
            "Route String": .int(Int64(parentLane)),
            "UID": .int(uid),
            "Vendor ID": .int(Int64(vendorID)),
            "Device ID": .int(Int64(deviceID)),
            "Device Vendor Name": .string(vendorName),
            "Device Model Name": .string(modelName),
            "Upstream Port Number": 1,
            "Max Port Number": .int(Int64(max(16, (adapters.map(\.portNumber) + downstreamLanes).max() ?? 0))),
            "Thunderbolt Version": 64,
            "Supported Link Speed": .int(Int64(link.supportedMask)),
            "Link Bandwidth": .int(Int64(link.bandwidth)),
        ]
        switches.append(RawThunderboltSwitch(
            node: RawNode(id: id, className: className, classChain: DemoClassChain.thunderboltSwitch(className),
                          name: className, location: String(parentLane), properties: PropertyBag(properties)),
            parentSwitchID: parent.id, ports: ports, ancestry: ancestry))
        return DemoSwitchRef(id: id, className: className, lanes: lanes, ancestry: ancestry)
    }

    /// Keys of a lane adapter (`Description` "Thunderbolt Port").
    private static func laneKeys(portNumber: Int, link: DemoThunderboltLink?) -> [String: PlistValue] {
        [
            "Description": "Thunderbolt Port",
            "Port Number": .int(Int64(portNumber)),
            "Adapter Type": 1,
            "Lane": .int(Int64((portNumber - 1) % 2)),
            "Dual-Link Port": .int(Int64(portNumber % 2 == 1 ? portNumber + 1 : portNumber - 1)),
            "Current Link Speed": .int(Int64(link?.speedCode ?? 0)),
            "Current Link Width": .int(Int64(link?.widthCode ?? 0)),
            "Target Link Width": .int(link == nil ? 0 : 3),
            "Supported Link Speed": .int(Int64(link?.supportedMask ?? 0xE)),
            "Link Bandwidth": .int(Int64(link?.bandwidth ?? 0)),
            "CLx State": 0,
        ]
    }

    private mutating func adapterNode(_ adapter: DemoThunderboltAdapter, switchID: UInt64) -> RawNode {
        let hops: PlistValue = adapter.isLive
            ? .array([.dict(["In HopID": 8, "Out HopID": 8, "Out Port": 1])])
            : .array([])
        let typeCodes = ["PCIe Adapter": 0x100101, "USB Gen T Adapter": 0x200101, "DP or HDMI Adapter": 0x0E0101,
                         "Thunderbolt Native Host Interface Adapter": 2]
        return RawNode(id: newID(), parentID: switchID, className: "IOThunderboltPort",
                       classChain: DemoClassChain.thunderboltPort, name: "IOThunderboltPort",
                       location: String(adapter.portNumber),
                       properties: [
                           "Description": .string(adapter.description),
                           "Port Number": .int(Int64(adapter.portNumber)),
                           "Adapter Type": .int(Int64(typeCodes[adapter.description] ?? 0)),
                           "Hop Table": hops,
                       ])
    }
}

// MARK: - Variation

/// Smooth, deterministic variation for demo power readings.
///
/// The app advances `tick` about every two seconds. A reading mixes a slow
/// and a faster sine wave, so sparklines move without looking periodic,
/// and never strays more than `amplitude` (a fraction) from its base value.
struct DemoWave {
    let tick: Int

    /// A multiplier within `1 ± amplitude`. Different `phase` values keep
    /// separate readings out of step with each other.
    func factor(amplitude: Double, phase: Double) -> Double {
        let t = Double(tick)
        let slow = sin(t * 2 * Double.pi / 37 + phase)
        let fast = sin(t * 2 * Double.pi / 11 + phase * 1.7)
        return 1 + amplitude * (0.7 * slow + 0.3 * fast)
    }

    /// `base` varied by `factor(amplitude:phase:)`.
    func value(_ base: Double, amplitude: Double, phase: Double) -> Double {
        base * factor(amplitude: amplitude, phase: phase)
    }
}
