import Foundation

/// A platform-neutral mirror of an IORegistry / property-list value.
///
/// IOKit hands back CoreFoundation objects (`CFString`, `CFNumber`, `CFBoolean`,
/// `CFData`, `CFArray`, `CFDictionary`, `CFDate`). `BusStopKit` converts them
/// into `PlistValue` so the rest of the pipeline is plain Swift, `Sendable`,
/// `Codable`, and testable on Linux.
///
/// JSON encoding is designed to stay readable in test fixtures:
/// strings, numbers, booleans, arrays and objects map directly; `Data` encodes
/// as `{"$data": "<base64>"}` and `Date` as `{"$date": "<ISO-8601>"}`.
/// Integral numbers decode as `.int`, other numbers as `.double`.
public enum PlistValue: Sendable, Hashable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case data(Data)
    case date(Date)
    case array([PlistValue])
    case dict([String: PlistValue])
}

// MARK: - Typed access

extension PlistValue {
    /// The value as a string. `Data` is decoded as UTF-8 with trailing NULs and
    /// whitespace removed (IOKit often stores C strings as `Data`).
    public var stringValue: String? {
        switch self {
        case .string(let s):
            return s
        case .data(let d):
            guard let s = String(data: d, encoding: .utf8) else { return nil }
            let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
            return trimmed.isEmpty ? nil : trimmed
        default:
            return nil
        }
    }

    /// The value as an integer. Accepts integers, integral doubles, booleans
    /// (0/1), decimal or `0x`-prefixed hexadecimal strings, and 1–8 byte `Data`
    /// (little-endian, as IOKit device-tree properties are stored).
    public var int64Value: Int64? {
        switch self {
        case .int(let i):
            return i
        case .double(let d):
            guard d.isFinite, d.rounded() == d, abs(d) < 9.2e18 else { return nil }
            return Int64(d)
        case .bool(let b):
            return b ? 1 : 0
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespaces)
            if t.lowercased().hasPrefix("0x") {
                return Int64(t.dropFirst(2), radix: 16)
            }
            return Int64(t)
        case .data(let d):
            guard (1...8).contains(d.count) else { return nil }
            var result: UInt64 = 0
            for (i, byte) in d.enumerated() {
                result |= UInt64(byte) << (8 * UInt64(i))
            }
            return Int64(bitPattern: result)
        default:
            return nil
        }
    }

    public var intValue: Int? { int64Value.flatMap { Int(exactly: $0) } }

    public var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// The value as a boolean. Accepts booleans, integers (non-zero is true) and
    /// the strings "Yes"/"No"/"true"/"false"/"1"/"0" (case-insensitive).
    public var boolValue: Bool? {
        switch self {
        case .bool(let b):
            return b
        case .int(let i):
            return i != 0
        case .double(let d):
            return d != 0
        case .string(let s):
            switch s.lowercased() {
            case "yes", "true", "1": return true
            case "no", "false", "0": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    public var dataValue: Data? {
        if case .data(let d) = self { return d }
        return nil
    }

    public var dateValue: Date? {
        if case .date(let d) = self { return d }
        return nil
    }

    public var arrayValue: [PlistValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var dictValue: [String: PlistValue]? {
        if case .dict(let d) = self { return d }
        return nil
    }

    /// An array of strings; non-string elements are skipped.
    public var stringArrayValue: [String]? {
        arrayValue.map { $0.compactMap(\.stringValue) }
    }

    /// A short human-readable rendering, used by the inspector's raw-key view.
    public var displayString: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "Yes" : "No"
        case .data(let d):
            let hex = d.prefix(32).map { String(format: "%02x", $0) }.joined()
            return "<\(hex)\(d.count > 32 ? "…" : "")>"
        case .date(let d): return ISO8601DateFormatter().string(from: d)
        case .array(let a): return "(" + a.map(\.displayString).joined(separator: ", ") + ")"
        case .dict(let d):
            return "{" + d.keys.sorted().map { "\($0)=\(d[$0]!.displayString)" }.joined(separator: ", ") + "}"
        }
    }
}

// MARK: - Codable

extension PlistValue: Codable {
    private enum SpecialKey {
        static let data = "$data"
        static let date = "$date"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([PlistValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: PlistValue].self) {
            if o.count == 1, let encoded = o[SpecialKey.data]?.stringValue,
               let data = Data(base64Encoded: encoded) {
                self = .data(data)
            } else if o.count == 1, let encoded = o[SpecialKey.date]?.stringValue,
                      let date = ISO8601DateFormatter().date(from: encoded) {
                self = .date(date)
            } else {
                self = .dict(o)
            }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported property-list value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d):
            // JSON has no NaN/Infinity; encode them as strings rather than failing.
            if d.isFinite { try container.encode(d) } else { try container.encode(String(d)) }
        case .bool(let b): try container.encode(b)
        case .data(let d): try container.encode([SpecialKey.data: d.base64EncodedString()])
        case .date(let d): try container.encode([SpecialKey.date: ISO8601DateFormatter().string(from: d)])
        case .array(let a): try container.encode(a)
        case .dict(let o): try container.encode(o)
        }
    }
}

// MARK: - Literals (handy for fixtures and demo data)

extension PlistValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: PlistValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, PlistValue)...) {
        self = .dict(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
