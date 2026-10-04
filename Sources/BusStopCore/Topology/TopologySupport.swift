import Foundation

/// Lookups over the captured port-controller nodes (`RawSnapshot.portNodes`).
///
/// Nodes are de-duplicated by registry ID (the first copy wins) and kept in
/// input order. Every walk is bounded and cycle-safe, so a malformed capture
/// cannot hang the builder.
struct TopologyNodeIndex {
    let nodes: [RawNode]
    let byID: [UInt64: RawNode]

    init(_ input: [RawNode]) {
        var seen = Set<UInt64>()
        var list: [RawNode] = []
        var map: [UInt64: RawNode] = [:]
        for node in input where seen.insert(node.id).inserted {
            list.append(node)
            map[node.id] = node
        }
        nodes = list
        byID = map
    }

    /// Captured ancestors of a node through `parentID`, nearest first.
    /// Stops at the first parent that was not captured.
    func ancestors(of node: RawNode, limit: Int = 64) -> [RawNode] {
        var result: [RawNode] = []
        var visited: Set<UInt64> = [node.id]
        var next = node.parentID
        while let id = next, result.count < limit, visited.insert(id).inserted, let parent = byID[id] {
            result.append(parent)
            next = parent.parentID
        }
        return result
    }
}

/// Class-name checks that also look at the recorded superclass chain, so a
/// driver subclass of a known class is still recognised.
enum TopologyClass {
    /// True when the node's class or a recorded superclass starts with `prefix`.
    static func has(_ node: RawNode, prefix: String) -> Bool {
        node.className.hasPrefix(prefix) || node.classChain.contains { $0.hasPrefix(prefix) }
    }

    /// The first of the class and its superclasses that starts with `prefix`.
    static func first(_ node: RawNode, prefix: String) -> String? {
        if node.className.hasPrefix(prefix) { return node.className }
        return node.classChain.first { $0.hasPrefix(prefix) }
    }

    /// True when the class or a recorded superclass contains `text`.
    static func mentions(_ node: RawNode, _ text: String) -> Bool {
        node.className.contains(text) || node.classChain.contains { $0.contains(text) }
    }
}

/// Small string helpers shared by the topology parsers.
enum TopologyText {
    /// Trims whitespace and NULs; returns nil for empty strings and for
    /// placeholder strings made only of "x" (Apple's AV adapter reports
    /// "xxxxxxxx" as its vendor).
    static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
        if trimmed.isEmpty { return nil }
        if trimmed.count >= 4, trimmed.allSatisfy({ $0 == "x" || $0 == "X" }) { return nil }
        return trimmed
    }

    /// Lowercased, with runs of whitespace collapsed, for name comparisons.
    static func normalized(_ value: String) -> String {
        value.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Lowercased words of a name, split on anything that is not a letter or digit.
    static func words(_ value: String) -> [String] {
        value.lowercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// How strongly two device names match.
    enum NameMatch: Int, Comparable {
        /// One name contains the other, and the shorter has at least 4 characters.
        case contains = 1
        /// The names are equal ignoring case and spacing.
        case exact = 2

        static func < (lhs: NameMatch, rhs: NameMatch) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Compares two names case-insensitively. Used to tie USB devices and
    /// displays to Thunderbolt chain devices; fails closed on short names.
    static func match(_ a: String?, _ b: String?) -> NameMatch? {
        guard let a = clean(a), let b = clean(b) else { return nil }
        let left = normalized(a)
        let right = normalized(b)
        if left == right { return .exact }
        let (shorter, longer) = left.count <= right.count ? (left, right) : (right, left)
        if shorter.count >= 4, longer.contains(shorter) { return .contains }
        return nil
    }

    /// Parses a registry path component such as `"Port-USB-C@2"` or
    /// `"Port-MagSafe 3@1"` into its type text and number. The number after
    /// `@` is hexadecimal, as `IORegistryEntryGetLocationInPlane` prints it.
    static func parsePortComponent(_ component: String) -> (typeText: String, number: Int)? {
        let trimmed = component.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
        guard trimmed.hasPrefix("Port-"), let at = trimmed.lastIndex(of: "@") else { return nil }
        let typeText = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<at])
        let digits = String(trimmed[trimmed.index(after: at)...])
        guard !typeText.isEmpty, !digits.isEmpty, digits.count <= 8, let number = Int(digits, radix: 16) else { return nil }
        return (typeText, number)
    }

    /// The last path component of a registry path (`"…/AppleHPMDevice@3F/Port-USB-C@2"`).
    static func lastPathComponent(_ path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.last.map(String.init)
    }

    /// The first path component of a transport description (`"Port-USB-C@2/USB3"`).
    static func firstPathComponent(_ path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        return parts.first.map(String.init)
    }

    /// The number after a fixed prefix in a registry name: `"apciec2"` → 2.
    /// The rest of the name must be digits only.
    static func indexedName(_ name: String, prefix: String) -> Int? {
        guard name.hasPrefix(prefix) else { return nil }
        let digits = name.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.count <= 6, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(digits)
    }

    /// Lowercase hexadecimal, zero-padded to `width` digits.
    static func hex(_ value: UInt64, width: Int) -> String {
        let digits = String(value, radix: 16)
        return digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    }

    /// Lowercase hexadecimal of a non-negative integer, zero-padded; negative
    /// values use their two's-complement bit pattern.
    static func hex(_ value: Int, width: Int) -> String {
        hex(UInt64(bitPattern: Int64(value)), width: width)
    }
}

/// Helpers for reading `PlistValue`s the builder treats specially.
enum TopologyValues {
    /// Whether a value is an empty collection or string. Nil when absent.
    static func isEmpty(_ value: PlistValue?) -> Bool? {
        guard let value else { return nil }
        switch value {
        case .array(let a): return a.isEmpty
        case .dict(let d): return d.isEmpty
        case .data(let d): return d.isEmpty
        case .string(let s): return s.isEmpty
        default: return false
        }
    }

    /// A telemetry reading in mW, tolerating unsigned encodings of negative
    /// numbers. `PowerTelemetryData` values such as `BatteryPower` are signed
    /// 64-bit integers that sometimes arrive as their unsigned bit pattern
    /// (a number near 2^64, possibly as a `Double` or a string). Anything
    /// above `Int64.max / 2` is either converted back from two's complement
    /// or, when it cannot be such a pattern, dropped.
    static func signedMilliwatts(_ value: PlistValue?) -> Int? {
        guard let value else { return nil }
        let half = Int64.max / 2
        switch value {
        case .int(let i):
            guard i <= half else { return nil }
            return Int(exactly: i)
        case .double(let d):
            guard d.isFinite else { return nil }
            if abs(d) <= Double(half) { return Int(exactly: d.rounded()) }
            // 2^64 is exactly representable; values in [2^63, 2^64) are an
            // unsigned bit pattern.
            guard d >= 9_223_372_036_854_775_808.0, d < 18_446_744_073_709_551_616.0 else { return nil }
            return Int(exactly: Int64(bitPattern: UInt64(d)))
        case .string(let s):
            let t = s.trimmingCharacters(in: .whitespaces)
            if let i = Int64(t) { return signedMilliwatts(.int(i)) }
            if let u = UInt64(t), u > UInt64(Int64.max) { return Int(exactly: Int64(bitPattern: u)) }
            return nil
        case .data, .bool:
            guard let i = value.int64Value else { return nil }
            return signedMilliwatts(.int(i))
        default:
            return nil
        }
    }

    /// A finite `Double` as an `Int`, or nil when out of range.
    static func int(_ value: Double) -> Int? {
        guard value.isFinite, abs(value) < 1e15 else { return nil }
        return Int(value.rounded())
    }
}
