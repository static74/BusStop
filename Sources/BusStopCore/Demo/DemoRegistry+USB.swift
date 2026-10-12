import Foundation

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
