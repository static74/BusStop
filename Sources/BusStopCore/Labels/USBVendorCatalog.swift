/// Vendor names for USB vendor IDs.
///
/// Data derived from the USB ID Repository's `usb.ids`
/// (http://www.linux-usb.org/usb.ids), used under the 3-clause BSD License.
/// See THIRD_PARTY_NOTICES.md. The rows live in the generated file
/// `USBVendorCatalog+Data.swift`; regenerate it with
/// `scripts/generate-usb-vendors.py` rather than editing it. The table is
/// built in, so looking a vendor up never touches the network.
public enum USBVendorCatalog {
    /// Vendor names keyed by vendor ID.
    private static let namesByID: [Int: String] = Dictionary(
        generatedVendors.map { ($0.id, $0.name) },
        uniquingKeysWith: { first, _ in first }
    )

    /// The vendor's name as `usb.ids` writes it ("Apple, Inc."), if known.
    public static func name(forVendorID vendorID: Int) -> String? {
        namesByID[vendorID]
    }
}
