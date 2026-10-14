import Testing
@testable import BusStopCore

@Suite("USB vendor catalogue")
struct USBVendorCatalogTests {
    @Test func looksUpWellKnownVendors() {
        #expect(USBVendorCatalog.name(forVendorID: 0x05AC) == "Apple, Inc.")
        #expect(USBVendorCatalog.name(forVendorID: 0x2109) == "VIA Labs, Inc.")
        #expect(USBVendorCatalog.name(forVendorID: 0x0BDA) == "Realtek Semiconductor Corp.")
    }

    @Test func unknownIDsHaveNoName() {
        #expect(USBVendorCatalog.name(forVendorID: 0x0000) == nil)
        #expect(USBVendorCatalog.name(forVendorID: 0xFFFF) == nil)
        #expect(USBVendorCatalog.name(forVendorID: 0x1_05AC) == nil)
    }

    @Test func generatedRowsAreSortedAndUnique() {
        let ids = USBVendorCatalog.generatedVendors.map(\.id)
        #expect(ids == ids.sorted())
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { (0...0xFFFF).contains($0) })
        #expect(USBVendorCatalog.generatedVendors.allSatisfy { !$0.name.isEmpty })
    }
}
