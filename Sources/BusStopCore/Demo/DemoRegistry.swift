import Foundation

/// Builds the raw IORegistry records of a demo Mac.
///
/// Every node uses the classes and keys a real Mac publishes, as seen in the
/// macOS 26.3 `IOPort`-plane dump, the iOS 27 dump and the key lists
/// `BusStopKit` reads, so a demo snapshot goes through exactly the same
/// `TopologyBuilder` code path as a live capture. Registry IDs are handed
/// out in call order, so building a scenario twice gives identical records.
///
/// The builders live in extensions: ports, transports and PD components
/// here, USB devices in `DemoRegistry+USB.swift` and Thunderbolt switches in
/// `DemoRegistry+Thunderbolt.swift`. They append to the record lists below.
struct DemoRegistry {
    /// Registry ID of the `IOPort` plane root, the parent of every port node.
    static let rootID: UInt64 = 0x1_0000_0100

    private var nextID: UInt64
    var portNodes: [RawNode] = []
    var usbDevices: [RawUSBDevice] = []
    var switches: [RawThunderboltSwitch] = []
    /// Port key → HPM controller `UUID` (the SMC join key).
    var controllerUUIDs: [String: String] = [:]
    /// USB addresses per controller bus, handed out in enumeration order.
    var usbAddresses: [UInt32: Int] = [:]

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
        let carriesUSB = state.active.contains("USB2") || state.active.contains("USB3")
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
            "IOAccessoryUSBActive": .bool(carriesUSB),
            "IOAccessoryUSBSuperSpeedActive": .bool(state.active.contains("USB3")),
            "IOAccessoryUSBConnectString": .string(carriesUSB ? "Host" : "None"),
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
