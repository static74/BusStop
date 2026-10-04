import BusStopCore
import CoreFoundation
import Foundation
import Testing
@testable import BusStopKit

@Suite("PlistBridge")
struct PlistBridgeTests {
    @Test func booleansAreNotNumbers() {
        #expect(PlistBridge.value(from: kCFBooleanTrue) == .bool(true))
        #expect(PlistBridge.value(from: kCFBooleanFalse) == .bool(false))
        #expect(PlistBridge.value(from: NSNumber(value: true)) == .bool(true))
        #expect(PlistBridge.value(from: NSNumber(value: 1)) == .int(1))
        #expect(PlistBridge.value(from: NSNumber(value: 0)) == .int(0))
    }

    @Test func integersAndFloats() {
        #expect(PlistBridge.value(from: NSNumber(value: 42)) == .int(42))
        #expect(PlistBridge.value(from: NSNumber(value: -536_854_518)) == .int(-536_854_518))
        #expect(PlistBridge.value(from: NSNumber(value: Int64.min)) == .int(Int64.min))
        #expect(PlistBridge.value(from: NSNumber(value: Int64.max)) == .int(Int64.max))
        #expect(PlistBridge.value(from: NSNumber(value: UInt32.max)) == .int(4_294_967_295))
        #expect(PlistBridge.value(from: NSNumber(value: 1.5)) == .double(1.5))

        var float: Float = 2.5
        let cfFloat = CFNumberCreate(kCFAllocatorDefault, .float32Type, &float)
        #expect(PlistBridge.value(from: cfFloat) == .double(2.5))
    }

    @Test func unsignedValuesAboveInt64MaxKeepTheirBitPattern() {
        #expect(PlistBridge.value(from: NSNumber(value: UInt64.max)) == .int(-1))
        #expect(PlistBridge.value(from: NSNumber(value: UInt64(1) << 63)) == .int(Int64.min))
        // OSKernelCPUSubtype from a real macOS 26.3 registry dump.
        let subtype: UInt64 = 18_446_744_072_635_809_794
        #expect(PlistBridge.value(from: NSNumber(value: subtype)) == .int(Int64(bitPattern: subtype)))
    }

    @Test func stringsDataAndDates() {
        #expect(PlistBridge.value(from: "Port-USB-C@1" as NSString) == .string("Port-USB-C@1"))
        let bytes: [UInt8] = [0x01, 0x00, 0x00, 0x00]
        #expect(PlistBridge.value(from: NSData(bytes: bytes, length: bytes.count)) == .data(Data(bytes)))
        #expect(PlistBridge.value(from: NSData()) == .data(Data()))
        let date = NSDate(timeIntervalSinceReferenceDate: 812_345_678)
        #expect(PlistBridge.value(from: date) == .date(Date(timeIntervalSinceReferenceDate: 812_345_678)))
    }

    @Test func dataIsCappedAt64KiB() {
        let bytes = [UInt8](repeating: 0xAB, count: 70_000)
        let value = PlistBridge.value(from: NSData(bytes: bytes, length: bytes.count))
        #expect(value?.dataValue?.count == PlistBridge.maxDataBytes)
        #expect(value?.dataValue?.first == 0xAB)
    }

    @Test func nestedContainers() throws {
        let inner = NSMutableDictionary()
        inner["k"] = NSNumber(value: 2.5)
        inner["flag"] = NSNumber(value: false)
        let array = NSMutableArray()
        array.add(NSNumber(value: 1))
        array.add(NSNumber(value: true))
        array.add("x" as NSString)
        array.add(inner)
        array.add(NSURL(fileURLWithPath: "/tmp"))  // unknown type: skipped
        let outer = NSMutableDictionary()
        outer["array"] = array
        outer["data"] = NSData(bytes: [UInt8]([1, 2, 3]), length: 3)
        outer["empty"] = NSDictionary()
        outer[NSNumber(value: 7)] = "non-string key" as NSString  // dropped
        outer["url"] = NSURL(fileURLWithPath: "/tmp")  // dropped

        let expected: PlistValue = [
            "array": [1, true, "x", ["k": 2.5, "flag": false]],
            "data": .data(Data([1, 2, 3])),
            "empty": [:],
        ]
        let value = PlistBridge.value(from: outer)
        #expect(value == expected)

        let bag = PlistBridge.bag(from: outer)
        #expect(bag.keys == ["array", "data", "empty"])
        #expect(bag.array("array")?.count == 4)

        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(PlistValue.self, from: encoded)
        #expect(decoded == expected)
    }

    @Test func setsBecomeArrays() {
        let set = NSSet(array: ["a" as NSString])
        #expect(PlistBridge.value(from: set) == .array(["a"]))
    }

    @Test func depthIsLimited() {
        var object: AnyObject = NSNumber(value: 1)
        for _ in 0..<(PlistBridge.maxDepth + 10) {
            object = NSArray(object: object)
        }
        let value = PlistBridge.value(from: object)
        #expect(value != nil)
        var depth = 0
        var current = value
        while case .array(let elements)? = current {
            depth += 1
            current = elements.first
        }
        #expect(depth <= PlistBridge.maxDepth + 1)
    }

    @Test func unknownTypesAreSkipped() {
        #expect(PlistBridge.value(from: NSURL(fileURLWithPath: "/tmp")) == nil)
        #expect(PlistBridge.value(from: NSNull()) == nil)
        #expect(PlistBridge.value(from: nil) == nil)
    }
}
