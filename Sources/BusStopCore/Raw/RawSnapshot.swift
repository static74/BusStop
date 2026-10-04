import Foundation

/// Everything Bus Stop read from the system at one moment, before any
/// interpretation.
///
/// `BusStopKit.RegistryCapture` fills this from IOKit on macOS. Tests and demo
/// mode build it by hand. `busstop --raw` prints it as JSON, which is how bug
/// reports turn into test fixtures. `TopologyBuilder` turns it into a
/// `HostSnapshot`.
public struct RawSnapshot: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var capturedAt: Date
    public var machine: MachineInfo

    /// Port controllers and everything below them: nodes of the `IOPort`
    /// registry plane (macOS 26+) merged with services matched by class
    /// (`IOAccessoryManager`, `IOPort`, `AppleHDMIPortController`,
    /// `IOPortTransportState*`, `IOPortFeature*`, `IOPortTransportComponent*`,
    /// `IOPortTransportProtocol*`). De-duplicated by registry ID.
    ///
    /// `parentID` is the parent in the `IOPort` plane when known, otherwise
    /// the nearest captured ancestor in the `IOService` plane.
    public var portNodes: [RawNode]

    /// Port key (`"<PortType>/<PortNumber>"`) → `UUID` of the HPM controller
    /// that owns the port (`AppleHPMDevice*` parent). Joins SMC power channels.
    public var portControllerUUIDs: [String: String]

    public var usbDevices: [RawUSBDevice]
    public var thunderboltSwitches: [RawThunderboltSwitch]

    /// Selected `AppleSmartBattery` properties (`AdapterDetails`,
    /// `PowerTelemetryData`, `PowerOutDetails`, `PortControllerInfo`,
    /// `ExternalConnected`, `IsCharging`, `FullyCharged`, `CurrentCapacity`,
    /// `MaxCapacity`, `NotChargingReason`, `BatteryInstalled`, `ChargerData`).
    /// Nil when the service does not exist.
    public var battery: PropertyBag?

    /// `IOPSCopyExternalPowerAdapterDetails()`; nil when no adapter is attached.
    public var adapter: PropertyBag?

    /// Live per-port power channels read from the SMC (D1…D4). Empty when the
    /// SMC could not be read.
    public var smcChannels: [SMCChannel]

    public var displays: [RawDisplay]

    /// Non-fatal problems met during capture ("SMC unavailable", …).
    public var captureNotes: [String]

    public init(
        schemaVersion: Int = RawSnapshot.currentSchemaVersion,
        capturedAt: Date,
        machine: MachineInfo,
        portNodes: [RawNode] = [],
        portControllerUUIDs: [String: String] = [:],
        usbDevices: [RawUSBDevice] = [],
        thunderboltSwitches: [RawThunderboltSwitch] = [],
        battery: PropertyBag? = nil,
        adapter: PropertyBag? = nil,
        smcChannels: [SMCChannel] = [],
        displays: [RawDisplay] = [],
        captureNotes: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.machine = machine
        self.portNodes = portNodes
        self.portControllerUUIDs = portControllerUUIDs
        self.usbDevices = usbDevices
        self.thunderboltSwitches = thunderboltSwitches
        self.battery = battery
        self.adapter = adapter
        self.smcChannels = smcChannels
        self.displays = displays
        self.captureNotes = captureNotes
    }
}

/// Facts about the Mac itself.
public struct MachineInfo: Sendable, Hashable, Codable {
    /// `sysctl hw.model`, e.g. `"Mac16,5"` or `"MacBookPro18,3"`.
    public var model: String
    /// `sysctl hw.targettype`, e.g. `"J514m"`. Optional.
    public var targetType: String?
    /// `machdep.cpu.brand_string`, e.g. `"Apple M5 Pro"`.
    public var chip: String?
    /// Marketing OS version, e.g. `"27.0.1"`.
    public var osVersion: String
    public var osBuild: String?
    /// Whether an internal battery is installed (`BatteryInstalled`).
    public var hasBattery: Bool
    /// The user-visible computer name. Redacted in exports by default.
    public var computerName: String?

    public init(model: String, targetType: String? = nil, chip: String? = nil, osVersion: String,
                osBuild: String? = nil, hasBattery: Bool, computerName: String? = nil) {
        self.model = model
        self.targetType = targetType
        self.chip = chip
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.hasBattery = hasBattery
        self.computerName = computerName
    }

    /// True unless the CPU brand string names a non-Apple chip. macOS 27 runs
    /// only on Apple silicon, so an unknown chip is assumed to be Apple's.
    public var isAppleSilicon: Bool {
        chip.map { $0.hasPrefix("Apple") } ?? true
    }
}

/// One IORegistry entry.
public struct RawNode: Sendable, Hashable, Codable, Identifiable {
    /// `IORegistryEntryGetRegistryEntryID`.
    public var id: UInt64
    public var parentID: UInt64?
    /// `IOObjectGetClass`, e.g. `"AppleHPMInterfaceType10"`.
    public var className: String
    /// Superclass chain from the class itself upward when the reader could
    /// determine it (e.g. `["AppleHPMInterfaceType10", "AppleHPMInterface",
    /// "AppleTCController", "IOAccessoryManagerUSBC", "IOAccessoryManager",
    /// "IOPort", "IOService", …]`). Empty when unknown.
    public var classChain: [String]
    /// `IORegistryEntryGetName`, e.g. `"Port-USB-C"`.
    public var name: String
    /// `IORegistryEntryGetLocationInPlane`, e.g. `"1"` (hex digits).
    public var location: String?
    public var properties: PropertyBag

    public init(id: UInt64, parentID: UInt64? = nil, className: String, classChain: [String] = [],
                name: String, location: String? = nil, properties: PropertyBag = [:]) {
        self.id = id
        self.parentID = parentID
        self.className = className
        self.classChain = classChain
        self.name = name
        self.location = location
        self.properties = properties
    }

    /// True when the class or any recorded superclass equals `name`.
    public func conforms(to name: String) -> Bool {
        className == name || classChain.contains(name)
    }

    /// `"<name>@<location>"` as shown by `ioreg`.
    public var registryPathComponent: String {
        location.map { "\(name)@\($0)" } ?? name
    }
}

/// An ancestor of a node in the `IOService` plane, nearest first.
public struct RawAncestor: Sendable, Hashable, Codable {
    public var id: UInt64
    public var className: String
    public var name: String
    public var location: String?

    public init(id: UInt64, className: String, name: String, location: String? = nil) {
        self.id = id
        self.className = className
        self.name = name
        self.location = location
    }
}

/// An `IOUSBHostDevice` plus what the reader learned about where it sits.
public struct RawUSBDevice: Sendable, Hashable, Codable, Identifiable {
    /// The device itself. `node.parentID` is unused; see `parentDeviceID`.
    public var node: RawNode
    /// Registry ID of the nearest `IOUSBHostDevice` ancestor (its hub), if any.
    public var parentDeviceID: UInt64?
    /// `IOService`-plane ancestors, nearest first, up to about 30 levels.
    /// Used to spot Thunderbolt-tunnelled controllers (`AppleUSBXHCITR`,
    /// dock xHCIs), `apciecN` / `usb-drdN` names and internal controllers.
    public var ancestry: [RawAncestor]
    /// `UsbIOPort` found on the nearest ancestor that has it (macOS 26+), a
    /// registry path ending in e.g. `"…/AppleHPMDevice@3F/Port-USB-C@2"`.
    public var usbIOPortPath: String?
    /// `port-number` (little-endian UInt32 `Data`) of the `usb-drdN`
    /// device-tree ancestor, if found.
    public var drdPortNumber: Int?
    /// Registry ID of the `IOPort`-plane parent (an `IOPortTransportStateUSB2`
    /// or `…USB3` node) when the device is directly attached (macOS 26+).
    public var ioPortParentID: UInt64?
    /// The device's `IOUSBHostInterface` children. Most devices report
    /// `bDeviceClass == 0` and declare their class per interface.
    public var interfaces: [RawUSBInterface]

    public var id: UInt64 { node.id }

    public init(node: RawNode, parentDeviceID: UInt64? = nil, ancestry: [RawAncestor] = [],
                usbIOPortPath: String? = nil, drdPortNumber: Int? = nil, ioPortParentID: UInt64? = nil,
                interfaces: [RawUSBInterface] = []) {
        self.node = node
        self.parentDeviceID = parentDeviceID
        self.ancestry = ancestry
        self.usbIOPortPath = usbIOPortPath
        self.drdPortNumber = drdPortNumber
        self.ioPortParentID = ioPortParentID
        self.interfaces = interfaces
    }

    private enum CodingKeys: String, CodingKey {
        case node, parentDeviceID, ancestry, usbIOPortPath, drdPortNumber, ioPortParentID, interfaces
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        node = try c.decode(RawNode.self, forKey: .node)
        parentDeviceID = try c.decodeIfPresent(UInt64.self, forKey: .parentDeviceID)
        ancestry = try c.decodeIfPresent([RawAncestor].self, forKey: .ancestry) ?? []
        usbIOPortPath = try c.decodeIfPresent(String.self, forKey: .usbIOPortPath)
        drdPortNumber = try c.decodeIfPresent(Int.self, forKey: .drdPortNumber)
        ioPortParentID = try c.decodeIfPresent(UInt64.self, forKey: .ioPortParentID)
        interfaces = try c.decodeIfPresent([RawUSBInterface].self, forKey: .interfaces) ?? []
    }
}

/// One `IOUSBHostInterface` of a USB device.
public struct RawUSBInterface: Sendable, Hashable, Codable {
    /// `bInterfaceClass` (e.g. 3 HID, 8 mass storage, 1 audio, 14 video).
    public var interfaceClass: Int
    public var interfaceSubClass: Int?
    public var interfaceProtocol: Int?
    /// `kUSBString` / `USB Interface Name`, when present.
    public var name: String?

    public init(interfaceClass: Int, interfaceSubClass: Int? = nil, interfaceProtocol: Int? = nil, name: String? = nil) {
        self.interfaceClass = interfaceClass
        self.interfaceSubClass = interfaceSubClass
        self.interfaceProtocol = interfaceProtocol
        self.name = name
    }
}

/// An `IOThunderboltSwitch*` (the host's own switch or a device's) with its
/// `IOThunderboltPort` children.
public struct RawThunderboltSwitch: Sendable, Hashable, Codable, Identifiable {
    public var node: RawNode
    /// Registry ID of the upstream switch; nil for a host-root switch.
    public var parentSwitchID: UInt64?
    /// `IOThunderboltPort` children (lane adapters, DP/PCIe/USB adapters).
    public var ports: [RawNode]
    /// `IOService`-plane ancestors, nearest first (to find `acioN`).
    public var ancestry: [RawAncestor]

    public var id: UInt64 { node.id }

    public init(node: RawNode, parentSwitchID: UInt64? = nil, ports: [RawNode] = [], ancestry: [RawAncestor] = []) {
        self.node = node
        self.parentSwitchID = parentSwitchID
        self.ports = ports
        self.ancestry = ancestry
    }
}

/// One SMC USB-C power channel (`D1`…`D4`).
public struct SMCChannel: Sendable, Hashable, Codable {
    /// Channel index 1…4. Not the port number.
    public var index: Int
    /// `DxUI`: HPM controller UUID, lowercase hex without dashes.
    public var uuid: String?
    /// `DxJV` in volts.
    public var volts: Double?
    /// `DxJI` in amps.
    public var amps: Double?
    /// `DxPR`: whether a contract is present.
    public var present: Bool?
    /// `DxMP` contract power in milliwatts, when published.
    public var contractMilliwatts: Int?
    /// `DxDE` description, when published.
    public var label: String?

    public init(index: Int, uuid: String? = nil, volts: Double? = nil, amps: Double? = nil,
                present: Bool? = nil, contractMilliwatts: Int? = nil, label: String? = nil) {
        self.index = index
        self.uuid = uuid
        self.volts = volts
        self.amps = amps
        self.present = present
        self.contractMilliwatts = contractMilliwatts
        self.label = label
    }
}

/// An online display as CoreGraphics reports it.
public struct RawDisplay: Sendable, Hashable, Codable, Identifiable {
    /// `CGDirectDisplayID`.
    public var id: UInt32
    public var name: String?
    public var vendorID: Int?
    public var productID: Int?
    public var serialNumber: Int?
    public var isBuiltin: Bool
    public var isMain: Bool
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var refreshHz: Double?

    public init(id: UInt32, name: String? = nil, vendorID: Int? = nil, productID: Int? = nil,
                serialNumber: Int? = nil, isBuiltin: Bool, isMain: Bool = false,
                pixelWidth: Int? = nil, pixelHeight: Int? = nil, refreshHz: Double? = nil) {
        self.id = id
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshHz = refreshHz
    }
}
