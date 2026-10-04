import Foundation

/// The physical connector type of a port.
public enum PortKind: String, Sendable, Hashable, Codable, CaseIterable {
    case usbC
    case magSafe
    case usbA
    case hdmi
    case thunderbolt
    case sdCard
    case unknown

    /// IOKit `PortType` codes seen in the wild: 2 = USB-C, 17 = MagSafe 3,
    /// 6 = HDMI (device tree). Other codes map to `.unknown`.
    public init(portType: Int?, description: String?) {
        let d = description?.lowercased() ?? ""
        if d.hasPrefix("usb-c") || d == "usbc" || d == "type-c" { self = .usbC; return }
        if d.hasPrefix("magsafe") { self = .magSafe; return }
        if d.hasPrefix("usb-a") || d == "usba" { self = .usbA; return }
        if d.hasPrefix("hdmi") { self = .hdmi; return }
        if d.hasPrefix("thunderbolt") { self = .thunderbolt; return }
        if d.hasPrefix("sd") { self = .sdCard; return }
        switch portType {
        case 2: self = .usbC
        case 17: self = .magSafe
        case 6: self = .hdmi
        default: self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .usbC: return "USB-C"
        case .magSafe: return "MagSafe"
        case .usbA: return "USB-A"
        case .hdmi: return "HDMI"
        case .thunderbolt: return "Thunderbolt"
        case .sdCard: return "SD Card"
        case .unknown: return "Port"
        }
    }

    /// Catalogue connector name used by `PortLocationCatalog`.
    public var catalogConnector: String {
        switch self {
        case .usbC: return "usb-c"
        case .magSafe: return "magsafe"
        case .usbA: return "usb-a"
        case .hdmi: return "hdmi"
        case .thunderbolt: return "thunderbolt"
        case .sdCard: return "sd"
        case .unknown: return "unknown"
        }
    }

    /// SF Symbol for the connector.
    public var symbolName: String {
        switch self {
        case .usbC, .thunderbolt: return "cable.connector"
        case .magSafe: return "bolt.fill"
        case .usbA: return "cable.connector.horizontal"
        case .hdmi: return "tv"
        case .sdCard: return "sdcard"
        case .unknown: return "questionmark.circle"
        }
    }

    /// Sort order for physical-order listings when no catalogue entry exists.
    public var sortRank: Int {
        switch self {
        case .magSafe: return 0
        case .usbC, .thunderbolt: return 1
        case .usbA: return 2
        case .hdmi: return 3
        case .sdCard: return 4
        case .unknown: return 5
        }
    }
}

/// Stable identity of a physical port: IOKit `PortType` plus `PortNumber`.
/// MagSafe and a USB-C port can share a number, so both parts are needed.
public struct PortKey: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public var type: Int
    public var number: Int

    public init(type: Int, number: Int) {
        self.type = type
        self.number = number
    }

    /// Parses `"2/1"`.
    public init?(_ string: String) {
        let parts = string.split(separator: "/")
        guard parts.count == 2, let t = Int(parts[0]), let n = Int(parts[1]) else { return nil }
        self.init(type: t, number: n)
    }

    public var description: String { "\(type)/\(number)" }

    public static func < (lhs: PortKey, rhs: PortKey) -> Bool {
        (lhs.type, lhs.number) < (rhs.type, rhs.number)
    }

    public static let usbCType = 2
    public static let magSafeType = 17
    public static let hdmiType = 6
    /// Synthetic type codes for ports that IOKit does not number.
    public static let usbAType = 1000
    public static let unknownType = 9999
}

/// Where a port's display name came from.
public enum LabelSource: String, Sendable, Hashable, Codable {
    /// The user renamed the port.
    case user
    /// Exact (connector, number) match in the model catalogue.
    case catalog
    /// Matched by rank among same-connector ports (non-contiguous numbering).
    case catalogRank
    /// Generic "USB-C 2".
    case generic
}

/// A port's human name, e.g. location "Left Front" for a USB-C port.
public struct PortLabel: Sendable, Hashable, Codable {
    /// Chassis location ("Left Front", "Rear") or a user-chosen name.
    public var location: String?
    public var source: LabelSource
    /// Connector name used in titles ("USB-C").
    public var connector: String
    /// The port number shown in generic names.
    public var number: Int

    public init(location: String?, source: LabelSource, connector: String, number: Int) {
        self.location = location
        self.source = source
        self.connector = connector
        self.number = number
    }

    /// "Left Front · USB-C", a user name as-is, or "USB-C 2".
    public var title: String {
        switch source {
        case .user:
            return location ?? "\(connector) \(number)"
        case .catalog, .catalogRank:
            if let location { return "\(location) · \(connector)" }
            return "\(connector) \(number)"
        case .generic:
            return "\(connector) \(number)"
        }
    }

    /// Short form for chips and graph nodes: "Left Front" or "USB-C 2".
    public var shortTitle: String {
        location ?? "\(connector) \(number)"
    }
}

/// An IOKit transport on a port.
public enum TransportKind: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    /// Configuration Channel: always active when anything is plugged into USB-C.
    case cc = "CC"
    case usb2 = "USB2"
    case usb3 = "USB3"
    case displayPort = "DisplayPort"
    /// Converged IO: Thunderbolt / USB4.
    case cio = "CIO"
    case hdmi = "HDMI"

    public init?(ioKitName: String) {
        switch ioKitName.uppercased() {
        case "CC": self = .cc
        case "USB2": self = .usb2
        case "USB3": self = .usb3
        case "DISPLAYPORT", "DP": self = .displayPort
        case "CIO", "USB4", "THUNDERBOLT": self = .cio
        case "HDMI": self = .hdmi
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .cc: return "Power/CC"
        case .usb2: return "USB 2"
        case .usb3: return "USB 3"
        case .displayPort: return "DisplayPort"
        case .cio: return "Thunderbolt"
        case .hdmi: return "HDMI"
        }
    }

    private var order: Int {
        switch self {
        case .cio: return 0
        case .usb3: return 1
        case .displayPort: return 2
        case .hdmi: return 3
        case .usb2: return 4
        case .cc: return 5
        }
    }

    public static func < (lhs: TransportKind, rhs: TransportKind) -> Bool { lhs.order < rhs.order }
}

/// One transport's state on a port.
public struct TransportInfo: Sendable, Hashable, Codable {
    public var kind: TransportKind
    public var isActive: Bool
    /// Carried inside a Thunderbolt/USB4 tunnel (a dock's USB3 or DP).
    public var isTunneled: Bool
    public var link: LinkInfo?
    /// Product named by the transport's metadata (USB2/DisplayPort), if any.
    public var productName: String?

    public init(kind: TransportKind, isActive: Bool, isTunneled: Bool = false, link: LinkInfo? = nil,
                productName: String? = nil) {
        self.kind = kind
        self.isActive = isActive
        self.isTunneled = isTunneled
        self.link = link
        self.productName = productName
    }
}

/// Direction of power through a port, from the Mac's point of view.
public enum PowerDirection: String, Sendable, Hashable, Codable {
    /// The Mac is charging from this port.
    case input
    /// The Mac is powering a device on this port.
    case output
    case none
}

/// How a power figure was obtained, best first.
public enum PowerReadingSource: String, Sendable, Hashable, Codable {
    /// Live SMC voltage × current for the port.
    case smc
    /// `AppleSmartBattery.PowerOutDetails`.
    case powerOutDetails
    /// Negotiated USB-PD contract (what the charger offers, not what flows).
    case pdContract
    /// System input power measured by the battery controller.
    case telemetry
    /// Sum of USB device power allocations (budget, not measurement).
    case usbAllocation
}

/// Power through one port.
public struct PortPower: Sendable, Hashable, Codable {
    public var direction: PowerDirection
    public var milliwatts: Int?
    public var millivolts: Int?
    public var milliamps: Int?
    public var source: PowerReadingSource
    /// True when the figure is measured rather than a budget or contract.
    public var isMeasured: Bool { source == .smc || source == .powerOutDetails || source == .telemetry }

    public init(direction: PowerDirection, milliwatts: Int?, millivolts: Int? = nil, milliamps: Int? = nil,
                source: PowerReadingSource) {
        self.direction = direction
        self.milliwatts = milliwatts
        self.millivolts = millivolts
        self.milliamps = milliamps
        self.source = source
    }
}

/// What the port's USB-PD cable e-marker reports, when available.
public struct CableInfo: Sendable, Hashable, Codable {
    public var isActive: Bool?
    public var isOptical: Bool?
    public var vendorID: Int?
    public var productID: Int?
    /// "Passive Cable", "Active Cable", …
    public var typeDescription: String?
    /// e.g. "USB4 Gen 3 (40 Gb/s)"
    public var speedDescription: String?
    /// Rated current in mA (3000 or 5000).
    public var currentRatingMilliamps: Int?
    /// USB-PD specification revision (2 = 3.0, 3 = 3.1 …).
    public var pdRevision: Int?

    public init(isActive: Bool? = nil, isOptical: Bool? = nil, vendorID: Int? = nil, productID: Int? = nil,
                typeDescription: String? = nil, speedDescription: String? = nil,
                currentRatingMilliamps: Int? = nil, pdRevision: Int? = nil) {
        self.isActive = isActive
        self.isOptical = isOptical
        self.vendorID = vendorID
        self.productID = productID
        self.typeDescription = typeDescription
        self.speedDescription = speedDescription
        self.currentRatingMilliamps = currentRatingMilliamps
        self.pdRevision = pdRevision
    }
}

/// Lifetime counters published by the port controller.
public struct PortStatistics: Sendable, Hashable, Codable {
    public var connectionCount: Int?
    public var plugEventCount: Int?
    public var overcurrentCount: Int?

    public init(connectionCount: Int? = nil, plugEventCount: Int? = nil, overcurrentCount: Int? = nil) {
        self.connectionCount = connectionCount
        self.plugEventCount = plugEventCount
        self.overcurrentCount = overcurrentCount
    }
}

/// One physical port on the Mac and everything attached to it.
public struct PhysicalPort: Sendable, Hashable, Codable, Identifiable {
    public var key: PortKey
    public var kind: PortKind
    public var number: Int
    /// `"Port-USB-C@1"`.
    public var registryName: String
    public var label: PortLabel
    /// Catalogue capability text, e.g. "Thunderbolt 5", "USB 3 (10 Gb/s)".
    public var capabilityDescription: String?
    /// `TransportsSupported`, minus CC.
    public var supportedTransports: [TransportKind]
    /// Active, non-tunnelled transports, fastest first. CC is omitted.
    public var activeTransports: [TransportInfo]
    /// Anything plugged in at all (including a charger or a bare cable).
    public var isConnected: Bool
    /// The fastest active data link.
    public var link: LinkInfo?
    public var power: PortPower?
    /// Set when the Mac is charging through this port.
    public var charger: ChargerInfo?
    public var cable: CableInfo?
    /// Device trees attached to this port (roots).
    public var devices: [DeviceNode]
    public var statistics: PortStatistics?
    public var liquidDetected: Bool
    /// Raw IORegistry properties of the port node, for the inspector.
    public var properties: PropertyBag?

    public var id: String { key.description }

    public init(key: PortKey, kind: PortKind, number: Int, registryName: String, label: PortLabel,
                capabilityDescription: String? = nil, supportedTransports: [TransportKind] = [],
                activeTransports: [TransportInfo] = [], isConnected: Bool = false, link: LinkInfo? = nil,
                power: PortPower? = nil, charger: ChargerInfo? = nil, cable: CableInfo? = nil,
                devices: [DeviceNode] = [], statistics: PortStatistics? = nil, liquidDetected: Bool = false,
                properties: PropertyBag? = nil) {
        self.key = key
        self.kind = kind
        self.number = number
        self.registryName = registryName
        self.label = label
        self.capabilityDescription = capabilityDescription
        self.supportedTransports = supportedTransports
        self.activeTransports = activeTransports
        self.isConnected = isConnected
        self.link = link
        self.power = power
        self.charger = charger
        self.cable = cable
        self.devices = devices
        self.statistics = statistics
        self.liquidDetected = liquidDetected
        self.properties = properties
    }

    /// Every device on this port, depth-first, with its depth (0 = root).
    public var allDevices: [(device: DeviceNode, depth: Int)] {
        devices.flatMap { $0.flattened(depth: 0) }
    }

    /// Number of devices on this port, counting every level.
    public var deviceCount: Int {
        devices.reduce(0) { $0 + 1 + $1.descendantCount }
    }

    /// Sum of USB power allocations on this port (bus-powered subtrees only).
    public var allocatedMilliwatts: Int {
        devices.reduce(0) { $0 + $1.rolledUpMilliwatts }
    }

    /// True when the port supports Thunderbolt / USB4.
    public var supportsThunderbolt: Bool { supportedTransports.contains(.cio) }
}
