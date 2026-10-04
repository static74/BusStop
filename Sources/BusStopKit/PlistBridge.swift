import BusStopCore
import CoreFoundation
import Foundation

/// Converts CoreFoundation property-list objects, as IOKit returns them, into
/// `PlistValue`.
///
/// Rules:
/// - `CFBoolean` is checked by type ID before `CFNumber`, so booleans never
///   turn into 0 or 1.
/// - Integer `CFNumber`s become `.int`. An unsigned 64-bit value above
///   `Int64.max` keeps its bit pattern (it reads back negative) instead of
///   trapping or being clamped.
/// - Floating-point `CFNumber`s become `.double`.
/// - `CFData` is capped at `maxDataBytes`; longer data keeps its prefix.
/// - `CFSet` (IOKit's `OSSet`) becomes an array.
/// - Dictionaries keep string keys only.
/// - Containers deeper than `maxDepth` and unknown types are skipped.
public enum PlistBridge {
    /// Largest `CFData` payload kept, in bytes.
    public static let maxDataBytes = 64 * 1024
    /// Deepest container nesting converted. Deeper values are dropped.
    public static let maxDepth = 24
    /// Most elements kept from one array, set or dictionary.
    public static let maxElements = 4096

    /// Converts one CF object. Returns nil for unknown types and for
    /// containers nested deeper than `maxDepth`.
    public static func value(from object: CFTypeRef?) -> PlistValue? {
        convert(object, depth: 0)
    }

    /// Converts a CF dictionary into a property bag (string keys only).
    public static func bag(from dictionary: CFDictionary) -> PropertyBag {
        PropertyBag(dictionaryValues(dictionary, depth: 0))
    }

    private static func convert(_ object: CFTypeRef?, depth: Int) -> PlistValue? {
        guard let object, depth <= maxDepth else { return nil }
        let typeID = CFGetTypeID(object)

        // CFBoolean must be tested before CFNumber: NSNumber-backed booleans
        // would otherwise read as integers.
        if typeID == CFBooleanGetTypeID() {
            return .bool(CFBooleanGetValue(unsafeDowncast(object, to: CFBoolean.self)))
        }
        if typeID == CFNumberGetTypeID() {
            return number(unsafeDowncast(object, to: CFNumber.self))
        }
        if typeID == CFStringGetTypeID() {
            return .string(unsafeDowncast(object, to: CFString.self) as String)
        }
        if typeID == CFDataGetTypeID() {
            return .data(data(unsafeDowncast(object, to: CFData.self)))
        }
        if typeID == CFDateGetTypeID() {
            let absolute = CFDateGetAbsoluteTime(unsafeDowncast(object, to: CFDate.self))
            return .date(Date(timeIntervalSinceReferenceDate: absolute))
        }
        if typeID == CFArrayGetTypeID() {
            return .array(arrayValues(unsafeDowncast(object, to: CFArray.self), depth: depth))
        }
        if typeID == CFDictionaryGetTypeID() {
            return .dict(dictionaryValues(unsafeDowncast(object, to: CFDictionary.self), depth: depth))
        }
        if typeID == CFSetGetTypeID() {
            return .array(setValues(unsafeDowncast(object, to: CFSet.self), depth: depth))
        }
        return nil
    }

    private static func number(_ number: CFNumber) -> PlistValue? {
        if CFNumberIsFloatType(number) {
            var double: Double = 0
            guard CFNumberGetValue(number, .float64Type, &double) else { return nil }
            return .double(double)
        }
        var int64: Int64 = 0
        if CFNumberGetValue(number, .sInt64Type, &int64) {
            return .int(int64)
        }
        // The conversion was lossy: the number does not fit a signed 64-bit
        // integer, which for IOKit means an unsigned 64-bit value above
        // Int64.max. Keep its bit pattern.
        let unsigned = (number as NSNumber).uint64Value
        return .int(Int64(bitPattern: unsigned))
    }

    private static func data(_ data: CFData) -> Data {
        let length = min(CFDataGetLength(data), maxDataBytes)
        guard length > 0 else { return Data() }
        var bytes = [UInt8](repeating: 0, count: length)
        CFDataGetBytes(data, CFRange(location: 0, length: length), &bytes)
        return Data(bytes)
    }

    private static func object(at pointer: UnsafeRawPointer?) -> CFTypeRef? {
        guard let pointer else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }

    private static func arrayValues(_ array: CFArray, depth: Int) -> [PlistValue] {
        let count = min(CFArrayGetCount(array), maxElements)
        guard count > 0 else { return [] }
        var result: [PlistValue] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            if let value = convert(object(at: CFArrayGetValueAtIndex(array, index)), depth: depth + 1) {
                result.append(value)
            }
        }
        return result
    }

    private static func setValues(_ set: CFSet, depth: Int) -> [PlistValue] {
        let count = CFSetGetCount(set)
        guard count > 0 else { return [] }
        var pointers = [UnsafeRawPointer?](repeating: nil, count: count)
        CFSetGetValues(set, &pointers)
        var result: [PlistValue] = []
        for pointer in pointers.prefix(maxElements) {
            if let value = convert(object(at: pointer), depth: depth + 1) {
                result.append(value)
            }
        }
        return result
    }

    private static func dictionaryValues(_ dictionary: CFDictionary, depth: Int) -> [String: PlistValue] {
        let count = CFDictionaryGetCount(dictionary)
        guard count > 0 else { return [:] }
        var keys = [UnsafeRawPointer?](repeating: nil, count: count)
        var values = [UnsafeRawPointer?](repeating: nil, count: count)
        CFDictionaryGetKeysAndValues(dictionary, &keys, &values)
        var result: [String: PlistValue] = [:]
        for index in 0..<min(count, maxElements) {
            guard let key = object(at: keys[index]), CFGetTypeID(key) == CFStringGetTypeID() else { continue }
            let name = unsafeDowncast(key, to: CFString.self) as String
            if let value = convert(object(at: values[index]), depth: depth + 1) {
                result[name] = value
            }
        }
        return result
    }
}
