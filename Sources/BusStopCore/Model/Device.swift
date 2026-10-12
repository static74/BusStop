import Foundation

/// Which bus a device was discovered on.
public enum DeviceBus: String, Sendable, Hashable, Codable {
    case usb
    case thunderbolt
    case displayPort
    case power
    case other
}

/// What a device is, for icons and grouping.
public enum DeviceKind: String, Sendable, Hashable, Codable, CaseIterable {
    case hub
    case dock
    case display
    case storage
    case keyboard
    case mouse
    case input
    case audio
    case camera
    case network
    case phone
    case tablet
    case printer
    case charger
    case thunderboltDevice
    case adapter
    case wireless
    case other

    public var displayName: String {
        switch self {
        case .hub: return "Hub"
        case .dock: return "Dock"
        case .display: return "Display"
        case .storage: return "Storage"
        case .keyboard: return "Keyboard"
        case .mouse: return "Mouse"
        case .input: return "Input device"
        case .audio: return "Audio"
        case .camera: return "Camera"
        case .network: return "Network adapter"
        case .phone: return "Phone"
        case .tablet: return "Tablet"
        case .printer: return "Printer"
        case .charger: return "Charger"
        case .thunderboltDevice: return "Thunderbolt device"
        case .adapter: return "Adapter"
        case .wireless: return "Wireless receiver"
        case .other: return "Device"
        }
    }

    /// SF Symbol used in lists and the graph.
    public var symbolName: String {
        switch self {
        case .hub: return "square.stack.3d.down.right"
        case .dock: return "dock.rectangle"
        case .display: return "display"
        case .storage: return "externaldrive.fill"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .input: return "gamecontroller"
        case .audio: return "headphones"
        case .camera: return "camera"
        case .network: return "network"
        case .phone: return "iphone"
        case .tablet: return "ipad"
        case .printer: return "printer"
        case .charger: return "powerplug.fill"
        case .thunderboltDevice: return "bolt.horizontal"
        case .adapter: return "cable.connector"
        case .wireless: return "dot.radiowaves.left.and.right"
        case .other: return "shippingbox"
        }
    }

    /// True for nodes that can have children (hubs, docks, displays with hubs).
    public var isContainer: Bool {
        switch self {
        case .hub, .dock, .display, .thunderboltDevice: return true
        default: return false
        }
    }
}

/// Power information for one device.
public struct DevicePower: Sendable, Hashable, Codable {
    /// Power the Mac (or upstream hub) allocated to the device, in mW.
    public var allocatedMilliwatts: Int?
    /// Where the figure came from.
    public var source: PowerReadingSource
    /// True for hubs that bring their own power supply. Their downstream
    /// draw does not count against the upstream port.
    public var isSelfPowered: Bool?

    public init(allocatedMilliwatts: Int?, source: PowerReadingSource = .usbAllocation, isSelfPowered: Bool? = nil) {
        self.allocatedMilliwatts = allocatedMilliwatts
        self.source = source
        self.isSelfPowered = isSelfPowered
    }
}

/// A device in a port's tree: USB device, hub, dock, Thunderbolt device or display.
public struct DeviceNode: Sendable, Hashable, Codable, Identifiable {
    /// Stable across refreshes while the device stays plugged in:
    /// `"usb:<locationID hex>:<vid hex>:<pid hex>"`, `"tb:<UID hex>"`,
    /// `"display:<vendor>:<product>:<serial>"`.
    public var id: String
    /// IORegistry entry ID, when the device came from the registry.
    public var registryID: UInt64?
    public var bus: DeviceBus
    public var kind: DeviceKind
    public var name: String
    public var vendorName: String?
    public var vendorID: Int?
    public var productID: Int?
    public var serialNumber: String?
    /// USB spec version from `bcdUSB` via `Format.bcdVersion`, e.g. "3.2". Nil for non-USB.
    public var usbVersion: String?
    /// `bDeviceClass`.
    public var deviceClass: Int?
    public var locationID: UInt32?
    /// Negotiated link to the upstream port/hub.
    public var link: LinkInfo?
    public var power: DevicePower?
    /// Reached through a Thunderbolt / USB4 tunnel.
    public var isTunneled: Bool
    /// Thunderbolt chain depth (1 = directly on the Mac), when known.
    public var chainDepth: Int?
    public var children: [DeviceNode]
    /// Raw IORegistry properties, for the inspector.
    public var properties: PropertyBag?

    public init(id: String, registryID: UInt64? = nil, bus: DeviceBus, kind: DeviceKind, name: String,
                vendorName: String? = nil, vendorID: Int? = nil, productID: Int? = nil, serialNumber: String? = nil,
                usbVersion: String? = nil, deviceClass: Int? = nil, locationID: UInt32? = nil, link: LinkInfo? = nil,
                power: DevicePower? = nil, isTunneled: Bool = false, chainDepth: Int? = nil,
                children: [DeviceNode] = [], properties: PropertyBag? = nil) {
        self.id = id
        self.registryID = registryID
        self.bus = bus
        self.kind = kind
        self.name = name
        self.vendorName = vendorName
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.usbVersion = usbVersion
        self.deviceClass = deviceClass
        self.locationID = locationID
        self.link = link
        self.power = power
        self.isTunneled = isTunneled
        self.chainDepth = chainDepth
        self.children = children
        self.properties = properties
    }

    /// Number of devices below this one, at every level.
    public var descendantCount: Int {
        children.reduce(0) { $0 + 1 + $1.descendantCount }
    }

    /// This device's allocation plus its descendants', stopping at
    /// self-powered hubs (their downstream draw comes from their own supply).
    public var rolledUpMilliwatts: Int {
        let own = power?.allocatedMilliwatts ?? 0
        if power?.isSelfPowered == true { return own }
        return own + children.reduce(0) { $0 + $1.rolledUpMilliwatts }
    }

    /// Sum of allocations of every descendant regardless of who powers them.
    public var downstreamMilliwatts: Int {
        children.reduce(0) { $0 + ($1.power?.allocatedMilliwatts ?? 0) + $1.downstreamMilliwatts }
    }

    /// This node and all descendants, depth-first, with depth.
    public func flattened(depth: Int = 0) -> [(device: DeviceNode, depth: Int)] {
        [(self, depth)] + children.flatMap { $0.flattened(depth: depth + 1) }
    }

    /// `"0x05ac:0x1234"` when both IDs are known.
    public var vendorProductIDString: String? {
        guard let vendorID, let productID else { return nil }
        return String(format: "0x%04x:0x%04x", vendorID, productID)
    }
}
