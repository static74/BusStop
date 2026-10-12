import Foundation
@testable import BusStopCore

/// Concise builders for raw IORegistry records used by the topology tests.
///
/// Defaults describe the common case (a built-in USB-C port, an active
/// transport, a USB device with a location ID), so each test only spells out
/// what it is about.
enum TopologyFixtures {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    /// A model ID that no catalogue knows, so labels and order stay generic.
    static let genericModel = "Mac99,1"

    static func machine(_ model: String = genericModel, hasBattery: Bool = true) -> MachineInfo {
        MachineInfo(model: model, chip: "Apple M5 Pro", osVersion: "27.0", hasBattery: hasBattery)
    }

    static func raw(model: String = genericModel, hasBattery: Bool = true, ports: [RawNode] = [],
                    usb: [RawUSBDevice] = [], thunderbolt: [RawThunderboltSwitch] = [], battery: PropertyBag? = nil,
                    adapter: PropertyBag? = nil, uuids: [String: String] = [:], smc: [SMCChannel] = [],
                    displays: [RawDisplay] = [], notes: [String] = []) -> RawSnapshot {
        RawSnapshot(capturedAt: date, machine: machine(model, hasBattery: hasBattery), portNodes: ports,
                    portControllerUUIDs: uuids, usbDevices: usb, thunderboltSwitches: thunderbolt, battery: battery,
                    adapter: adapter, smcChannels: smc, displays: displays, captureNotes: notes)
    }

    // MARK: - Port-controller nodes

    /// A physical port node (`AppleHPMInterfaceType10` by default).
    static func port(id: UInt64, type: Int? = 2, number: Int, description: String = "USB-C",
                     connected: Bool = false, supported: [String] = ["CC", "USB2", "USB3", "DisplayPort", "CIO"],
                     active: [String]? = nil, className: String = "AppleHPMInterfaceType10",
                     extra: [String: PlistValue] = [:]) -> RawNode {
        let registryName = "Port-\(description)@\(String(number, radix: 16))"
        var p: [String: PlistValue] = [
            "PortTypeDescription": .string(description),
            "PortNumber": .int(Int64(number)),
            "BuiltIn": true,
            "ConnectionActive": .bool(connected),
            "TransportsSupported": .array(supported.map(PlistValue.string)),
            "TransportsActive": .array((active ?? (connected ? ["CC"] : [])).map(PlistValue.string)),
            "PortDescription": .string(registryName),
        ]
        if let type { p["PortType"] = .int(Int64(type)) }
        for (key, value) in extra { p[key] = value }
        return RawNode(id: id, parentID: 0x1_0000_0100, className: className, name: "Port-\(description)",
                       location: String(number, radix: 16), properties: PropertyBag(p))
    }

    /// An `IOPortTransportState*` node under a port.
    static func transport(id: UInt64, parent: UInt64?, kind: String, portType: Int = 2, portNumber: Int,
                          active: Bool? = true, tunneled: Bool = false, path: String? = nil,
                          extra: [String: PlistValue] = [:]) -> RawNode {
        var p: [String: PlistValue] = [
            "TransportTypeDescription": .string(kind),
            "ParentPortType": .int(Int64(portType)),
            "ParentPortNumber": .int(Int64(portNumber)),
            "Tunneled": .bool(tunneled),
            "TransportDescription": .string(path ?? "Port-USB-C@\(String(portNumber, radix: 16))/\(kind)"),
        ]
        if let active { p["Active"] = .bool(active) }
        for (key, value) in extra { p[key] = value }
        return RawNode(id: id, parentID: parent, className: "IOPortTransportState\(kind)", name: kind,
                       properties: PropertyBag(p))
    }

    /// Any other port-controller node (feature, PD component, protocol).
    static func node(id: UInt64, parent: UInt64?, className: String, name: String,
                     properties: [String: PlistValue] = [:]) -> RawNode {
        RawNode(id: id, parentID: parent, className: className, name: name, properties: PropertyBag(properties))
    }

    // MARK: - USB

    /// An `IOUSBHostDevice`. `speed` is `UsbLinkSpeed` in bits/s.
    static func usb(id: UInt64, parent: UInt64? = nil, name: String, vendor: Int = 0x1234, product: Int = 0x5678,
                    location: UInt32? = nil, speed: Int64? = 480_000_000, allocation: Int? = 100,
                    deviceClass: Int = 0, bcdUSB: Int = 0x0200, vendorName: String? = nil,
                    path: String? = nil, ioPortParent: UInt64? = nil, drd: Int? = nil,
                    ancestry: [RawAncestor] = [], interfaces: [RawUSBInterface] = [],
                    extra: [String: PlistValue] = [:]) -> RawUSBDevice {
        var p: [String: PlistValue] = [
            "USB Product Name": .string(name),
            "idVendor": .int(Int64(vendor)),
            "idProduct": .int(Int64(product)),
            "bDeviceClass": .int(Int64(deviceClass)),
            "bcdUSB": .int(Int64(bcdUSB)),
            "USBPortType": 5,
        ]
        if let location { p["locationID"] = .int(Int64(location)) }
        if let speed { p["UsbLinkSpeed"] = .int(speed) }
        if let allocation { p["UsbPowerSinkAllocation"] = .int(Int64(allocation)) }
        if let vendorName { p["USB Vendor Name"] = .string(vendorName) }
        for (key, value) in extra { p[key] = value }
        let node = RawNode(id: id, className: "IOUSBHostDevice", name: name,
                           location: location.map { TopologyText.hex(UInt64($0), width: 8) }, properties: PropertyBag(p))
        return RawUSBDevice(node: node, parentDeviceID: parent, ancestry: ancestry, usbIOPortPath: path,
                            drdPortNumber: drd, ioPortParentID: ioPortParent, interfaces: interfaces)
    }

    /// The native controller chain of an Apple-silicon USB-C port.
    static func nativeAncestry(drd: Int) -> [RawAncestor] {
        [
            RawAncestor(id: 0x9_0000 + UInt64(drd) * 16 + 1, className: "AppleUSB30XHCITypeCPort",
                        name: "usb-drd\(drd)-port-ss"),
            RawAncestor(id: 0x9_0000 + UInt64(drd) * 16 + 2, className: "AppleT8132USBXHCI", name: "AppleT8132USBXHCI"),
            RawAncestor(id: 0x9_0000 + UInt64(drd) * 16 + 3, className: "AppleARMIODevice", name: "usb-drd\(drd)"),
        ]
    }

    /// The controller chain of a device tunnelled through Thunderbolt on `apciecN`.
    static func tunnelAncestry(pcie: Int, base: UInt64 = 0xA_0000) -> [RawAncestor] {
        [
            RawAncestor(id: base + 1, className: "AppleUSB30XHCIPort", name: "AppleUSB30XHCIPort"),
            RawAncestor(id: base + 2, className: "AppleUSBXHCITR", name: "AppleUSBXHCITR"),
            RawAncestor(id: base + 3, className: "IOPCI2PCIBridge", name: "pci-bridge"),
            RawAncestor(id: base + 4, className: "IOPCI2PCIBridge", name: "pci-bridge"),
            RawAncestor(id: base + 5, className: "AppleT6050PCIeC", name: "apciec\(pcie)"),
        ]
    }

    // MARK: - Thunderbolt

    /// An `IOThunderboltPort` lane adapter.
    static func lane(id: UInt64, portNumber: Int, socket: String? = nil, speed: Int, width: Int,
                     extra: [String: PlistValue] = [:]) -> RawNode {
        var p: [String: PlistValue] = [
            "Description": "Thunderbolt Port",
            "Port Number": .int(Int64(portNumber)),
            "Current Link Speed": .int(Int64(speed)),
            "Current Link Width": .int(Int64(width)),
        ]
        if let socket { p["Socket ID"] = .string(socket) }
        for (key, value) in extra { p[key] = value }
        return RawNode(id: id, className: "IOThunderboltPort", name: "IOThunderboltPort",
                       location: String(portNumber), properties: PropertyBag(p))
    }

    /// A protocol adapter (`"DP or HDMI Adapter"`, `"USB Adapter"`, `"PCIe Adapter"`).
    static func adapter(id: UInt64, portNumber: Int, description: String, hops: Bool) -> RawNode {
        RawNode(id: id, className: "IOThunderboltPort", name: "IOThunderboltPort", location: String(portNumber),
                properties: [
                    "Description": .string(description),
                    "Port Number": .int(Int64(portNumber)),
                    "Hop Table": hops ? PlistValue.array([.dict(["Dst Port": .int(1)])]) : PlistValue.array([]),
                ])
    }

    /// An `IOThunderboltSwitch`.
    static func tbSwitch(id: UInt64, parent: UInt64? = nil, depth: Int, uid: Int64? = nil, vendor: String? = nil,
                         model: String? = nil, upstreamPort: Int? = nil, ports: [RawNode] = [],
                         ancestry: [RawAncestor] = []) -> RawThunderboltSwitch {
        var p: [String: PlistValue] = ["Depth": .int(Int64(depth))]
        if let uid { p["UID"] = .int(uid) }
        if let vendor { p["Device Vendor Name"] = .string(vendor) }
        if let model { p["Device Model Name"] = .string(model) }
        if let upstreamPort { p["Upstream Port Number"] = .int(Int64(upstreamPort)) }
        let node = RawNode(id: id, className: "IOThunderboltSwitchType7", name: "IOThunderboltSwitchType7",
                           properties: PropertyBag(p))
        return RawThunderboltSwitch(node: node, parentSwitchID: parent, ports: ports, ancestry: ancestry)
    }

    /// The registry ancestry of a host-root switch under `acioN`.
    static func hostAncestry(acio: Int) -> [RawAncestor] {
        [
            RawAncestor(id: 0xB_0000 + UInt64(acio) * 16 + 1, className: "IOThunderboltControllerType7",
                        name: "IOThunderboltControllerType7"),
            RawAncestor(id: 0xB_0000 + UInt64(acio) * 16 + 2, className: "AppleThunderboltHALType7",
                        name: "AppleThunderboltHALType7"),
            RawAncestor(id: 0xB_0000 + UInt64(acio) * 16 + 3, className: "AppleARMIODevice", name: "acio\(acio)"),
        ]
    }

    // MARK: - Helpers

    /// Every device in a snapshot, depth-first, keyed by name. The first of
    /// several equally named devices wins.
    static func devicesByName(_ snapshot: HostSnapshot) -> [String: DeviceNode] {
        var result: [String: DeviceNode] = [:]
        for entry in snapshot.allDevices where result[entry.device.name] == nil {
            result[entry.device.name] = entry.device
        }
        return result
    }
}
