import BusStopCore
import CoreGraphics
import Foundation
import IOKit

/// Reads online displays from CoreGraphics and, when the framebuffer
/// publishes them, their product names from the IORegistry.
enum DisplayReader {
    /// Most displays listed.
    static let maxDisplays: UInt32 = 32

    static func read(notes: inout [String]) -> [RawDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        let error = CGGetOnlineDisplayList(maxDisplays, &ids, &count)
        guard error == .success else {
            notes.append("CoreGraphics display list unavailable (error \(error.rawValue))")
            return []
        }
        let online = ids.prefix(Int(min(count, maxDisplays)))
        guard !online.isEmpty else { return [] }

        let framebuffers = framebufferProducts()
        return online.map { id in
            let vendor = Int(CGDisplayVendorNumber(id))
            let model = Int(CGDisplayModelNumber(id))
            let serial = Int(CGDisplaySerialNumber(id))
            var display = RawDisplay(
                id: id,
                name: name(vendor: vendor, model: model, serial: serial, in: framebuffers),
                vendorID: vendor,
                productID: model,
                serialNumber: serial == 0 ? nil : serial,
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: CGDisplayIsMain(id) != 0
            )
            if let mode = CGDisplayCopyDisplayMode(id) {
                display.pixelWidth = mode.pixelWidth > 0 ? mode.pixelWidth : nil
                display.pixelHeight = mode.pixelHeight > 0 ? mode.pixelHeight : nil
                let refresh = mode.refreshRate
                display.refreshHz = refresh.isFinite && refresh > 0 ? refresh : nil
            }
            return display
        }
    }

    /// `DisplayAttributes.ProductAttributes` of one framebuffer.
    struct FramebufferProduct: Equatable {
        var name: String
        var productID: Int?
        var vendorID: Int?
        var serialNumber: Int?
    }

    /// Product attributes published by Apple silicon framebuffers
    /// (`IOMobileFramebufferShim`, `AppleCLCD2`).
    static func framebufferProducts() -> [FramebufferProduct] {
        var result: [FramebufferProduct] = []
        var seen = Set<UInt64>()
        for className in ["IOMobileFramebufferShim", "AppleCLCD2"] {
            for entry in RegistryEntry.matching(className: className) {
                guard let id = entry.entryID, seen.insert(id).inserted,
                      let attributes = entry.property("DisplayAttributes")?.dictValue,
                      let product = attributes["ProductAttributes"]?.dictValue,
                      let name = product["ProductName"]?.stringValue, !name.isEmpty else { continue }
                result.append(FramebufferProduct(
                    name: name,
                    productID: product["ProductID"]?.intValue,
                    vendorID: product["LegacyManufacturerID"]?.intValue,
                    serialNumber: product["SerialNumber"]?.intValue
                ))
            }
        }
        return result
    }

    /// The framebuffer product name for a display, when exactly one name
    /// matches its product ID (narrowed by vendor and serial when known).
    static func name(vendor: Int, model: Int, serial: Int, in products: [FramebufferProduct]) -> String? {
        var candidates = products.filter { $0.productID == model }
        candidates = candidates.filter { $0.vendorID == nil || $0.vendorID == vendor }
        if Set(candidates.map(\.name)).count > 1, serial != 0 {
            candidates = candidates.filter { $0.serialNumber == serial }
        }
        let names = Set(candidates.map(\.name))
        return names.count == 1 ? names.first : nil
    }
}
