import BusStopCore
import Foundation
import IOKit

/// Reads every `IOUSBHostDevice` with the context needed to place it on a
/// physical port: ancestry, parent hub, `UsbIOPort` path, `usb-drdN` port
/// number, `IOPort`-plane parent and interfaces.
enum USBDeviceReader {
    /// `IOService`-plane ancestors recorded per device.
    static let maxAncestors = 30

    static func read(rootID: UInt64?) -> [RawUSBDevice] {
        var devices: [RawUSBDevice] = []
        var seen = Set<UInt64>()
        for entry in RegistryEntry.matching(className: "IOUSBHostDevice") {
            guard let id = entry.entryID, seen.insert(id).inserted, let className = entry.className else { continue }
            devices.append(readDevice(entry, id: id, className: className, rootID: rootID))
        }
        return devices
    }

    private static func readDevice(_ entry: RegistryEntry, id: UInt64, className: String,
                                   rootID: UInt64?) -> RawUSBDevice {
        // Per-key reads: USB devices can be torn down while being read.
        let properties = entry.properties(keys: RegistryKeys.usbDevice)
        let node = RawNode(
            id: id,
            className: className,
            classChain: ClassHierarchy.chain(for: className),
            name: entry.name ?? className,
            location: entry.location(in: RegistryPlane.service),
            properties: PropertyBag(properties)
        )

        var ancestry: [RawAncestor] = []
        var parentDeviceID: UInt64?
        var drdPortNumber: Int?
        var sawDRD = false
        var current = entry.parent(in: RegistryPlane.service)
        while let ancestor = current, ancestry.count < maxAncestors {
            let ancestorClass = ancestor.className ?? ""
            let ancestorName = ancestor.name ?? ""
            let ancestorID = ancestor.entryID ?? 0
            ancestry.append(RawAncestor(
                id: ancestorID,
                className: ancestorClass,
                name: ancestorName,
                location: ancestor.location(in: RegistryPlane.service)
            ))
            if parentDeviceID == nil, ancestor.conforms(to: "IOUSBHostDevice") {
                parentDeviceID = ancestorID
            }
            if !sawDRD, ancestorName.hasPrefix("usb-drd") {
                sawDRD = true
                drdPortNumber = portNumber(of: ancestor)
            }
            current = ancestor.parent(in: RegistryPlane.service)
        }

        let usbIOPortPath = entry.searchProperty("UsbIOPort", plane: RegistryPlane.service, parents: true)?
            .stringValue
        var ioPortParentID: UInt64?
        if let parent = entry.parent(in: RegistryPlane.port), let parentID = parent.entryID, parentID != rootID {
            ioPortParentID = parentID
        }

        return RawUSBDevice(
            node: node,
            parentDeviceID: parentDeviceID,
            ancestry: ancestry,
            usbIOPortPath: usbIOPortPath.flatMap { $0.isEmpty ? nil : $0 },
            drdPortNumber: drdPortNumber,
            ioPortParentID: ioPortParentID,
            interfaces: interfaces(of: entry)
        )
    }

    /// `port-number` of a `usb-drdN` node: a little-endian `UInt32` stored as
    /// `Data` (device-tree property), sometimes a plain number.
    private static func portNumber(of drd: RegistryEntry) -> Int? {
        if let value = drd.property("port-number")?.intValue { return value }
        // The same node seen through the device-tree plane.
        if drd.isInPlane(RegistryPlane.deviceTree) {
            return drd.searchProperty("port-number", plane: RegistryPlane.deviceTree, parents: false)?.intValue
        }
        return nil
    }

    private static func interfaces(of entry: RegistryEntry) -> [RawUSBInterface] {
        var result: [RawUSBInterface] = []
        for child in entry.children(in: RegistryPlane.service) where child.conforms(to: "IOUSBHostInterface") {
            let values = PropertyBag(child.properties(keys: RegistryKeys.usbInterface))
            guard let interfaceClass = values.int("bInterfaceClass") else { continue }
            var name = values.string(["kUSBString", "USB Interface Name"])
            if name == nil, let registryName = child.name, !registryName.isEmpty,
               !registryName.hasPrefix("IOUSBHostInterface"), registryName != child.className {
                name = registryName
            }
            result.append(RawUSBInterface(
                interfaceClass: interfaceClass,
                interfaceSubClass: values.int("bInterfaceSubClass"),
                interfaceProtocol: values.int("bInterfaceProtocol"),
                name: name
            ))
        }
        return result
    }
}
