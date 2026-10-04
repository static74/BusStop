import Foundation
import Testing
@testable import BusStopCore

@Suite("PlistValue")
struct PlistValueTests {
    @Test func roundTripsThroughJSON() throws {
        let value: PlistValue = [
            "name": "Port-USB-C@1",
            "number": 1,
            "ratio": 1.5,
            "active": true,
            "transports": ["CC", "USB2"],
            "raw": .data(Data([0x01, 0x00, 0x00, 0x00])),
        ]
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(PlistValue.self, from: data)
        #expect(decoded == value)
    }

    @Test func forgivingAccessors() {
        #expect(PlistValue.string("Yes").boolValue == true)
        #expect(PlistValue.int(0).boolValue == false)
        #expect(PlistValue.string("0x1F").intValue == 31)
        #expect(PlistValue.data(Data([0x02, 0x00, 0x00, 0x00])).intValue == 2)
        #expect(PlistValue.data(Data("Port-USB-C@2\0".utf8)).stringValue == "Port-USB-C@2")
        #expect(PlistValue.double(3.0).intValue == 3)
        #expect(PlistValue.double(3.5).intValue == nil)
    }
}
