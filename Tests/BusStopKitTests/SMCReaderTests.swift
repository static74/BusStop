import BusStopCore
import Foundation
import Testing
@testable import BusStopKit

@Suite("SMCReader")
struct SMCReaderTests {
    @Test func paramStructIs80Bytes() {
        #expect(MemoryLayout<SMCParamStruct>.stride == 80)
        #expect(MemoryLayout<SMCParamStruct>.size == 80)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.keyInfo) == 28)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.result) == 40)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data8) == 42)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data32) == 44)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.bytes) == 48)
        #expect(SMCReader.hasExpectedLayout)
    }

    @Test func fourCharacterCodes() {
        #expect(SMCReader.fourCC("D1UI") == 0x4431_5549)
        #expect(SMCReader.fourCC("flt ") == 0x666C_7420)
        #expect(SMCReader.fourCC("TOOLONG") == nil)
        #expect(SMCReader.fourCCString(0x666C_7420) == "flt ")
    }

    @Test func decoders() {
        // 20.0 as a little-endian float.
        let twenty = SMCReader.KeyValue(type: "flt ", bytes: [0x00, 0x00, 0xA0, 0x41])
        #expect(SMCReader.decodeFloat(twenty) == 20.0)
        #expect(SMCReader.decodeFloat(SMCReader.KeyValue(type: "ui32", bytes: [0, 0, 0xA0, 0x41])) == nil)
        #expect(SMCReader.decodeFloat(SMCReader.KeyValue(type: "flt ", bytes: [0, 0, 0xC0, 0x7F])) == nil)  // NaN
        #expect(SMCReader.decodeBigEndianInt([0x00, 0x00, 0x4E, 0x20]) == 20_000)
        #expect(SMCReader.decodeBigEndianInt([]) == nil)
        #expect(SMCReader.decodeHex([0xAB, 0x01]) == "ab01")
        #expect(SMCReader.decodeHex([0, 0, 0]) == nil)
        #expect(SMCReader.decodeString(Array("usb host\0\0".utf8)) == "usb host")
        #expect(SMCReader.decodeString([0, 0]) == nil)
    }

    @Test func channelsFromRecordedKeys() {
        let keys: [String: SMCReader.KeyValue] = [
            "D1UI": .init(type: "hex_", bytes: [0x12, 0x34, 0x00, 0xFF]),
            "D1JV": .init(type: "flt ", bytes: [0x00, 0x00, 0xA0, 0x40]),  // 5 V
            "D1JI": .init(type: "flt ", bytes: [0x00, 0x00, 0x00, 0x3F]),  // 0.5 A
            "D1PR": .init(type: "ui8 ", bytes: [0x01]),
            "D1MP": .init(type: "ui32", bytes: [0x00, 0x00, 0x75, 0x30]),  // 30000 mW
            "D3UI": .init(type: "hex_", bytes: [0x00, 0x00]),
            "D3PR": .init(type: "ui8 ", bytes: [0x00]),
        ]
        let channels = SMCReader.buildChannels { keys[$0] }
        #expect(channels.count == 2)
        #expect(channels.first == SMCChannel(index: 1, uuid: "123400ff", volts: 5, amps: 0.5, present: true,
                                             contractMilliwatts: 30_000, label: nil))
        #expect(channels.last?.index == 3)
        #expect(channels.last?.uuid == nil)
        #expect(channels.last?.present == false)
        #expect(SMCReader.buildChannels { _ in nil }.isEmpty)
    }
}
