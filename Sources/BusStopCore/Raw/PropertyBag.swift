import Foundation

/// The properties of one IORegistry entry, with forgiving typed accessors.
///
/// Apple does not treat most of these keys as API (anything prefixed `Apple`
/// in particular), so every accessor returns an optional and tolerates the
/// wrong type rather than trapping.
public struct PropertyBag: Sendable, Hashable, Codable, ExpressibleByDictionaryLiteral {
    public var values: [String: PlistValue]

    public init(_ values: [String: PlistValue] = [:]) {
        self.values = values
    }

    public init(dictionaryLiteral elements: (String, PlistValue)...) {
        self.values = Dictionary(elements, uniquingKeysWith: { _, last in last })
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([String: PlistValue].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    public subscript(key: String) -> PlistValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public var isEmpty: Bool { values.isEmpty }
    public var keys: [String] { values.keys.sorted() }
    public func has(_ key: String) -> Bool { values[key] != nil }

    // MARK: Single-key accessors

    public func string(_ key: String) -> String? { values[key]?.stringValue }
    public func int(_ key: String) -> Int? { values[key]?.intValue }
    public func int64(_ key: String) -> Int64? { values[key]?.int64Value }
    public func double(_ key: String) -> Double? { values[key]?.doubleValue }
    public func bool(_ key: String) -> Bool? { values[key]?.boolValue }
    public func data(_ key: String) -> Data? { values[key]?.dataValue }
    public func array(_ key: String) -> [PlistValue]? { values[key]?.arrayValue }
    public func strings(_ key: String) -> [String]? { values[key]?.stringArrayValue }

    /// A nested dictionary as its own bag.
    public func bag(_ key: String) -> PropertyBag? {
        values[key]?.dictValue.map(PropertyBag.init)
    }

    /// An array of dictionaries as bags; non-dictionary elements are skipped.
    public func bags(_ key: String) -> [PropertyBag]? {
        array(key).map { $0.compactMap { $0.dictValue.map(PropertyBag.init) } }
    }

    // MARK: First-present accessors (keys tried in order)

    public func string(_ keys: [String]) -> String? {
        for key in keys { if let v = string(key), !v.isEmpty { return v } }
        return nil
    }

    public func int(_ keys: [String]) -> Int? {
        for key in keys { if let v = int(key) { return v } }
        return nil
    }

    public func bool(_ keys: [String]) -> Bool? {
        for key in keys { if let v = bool(key) { return v } }
        return nil
    }

    /// Keeps only the given keys. Used to keep exports and snapshots small.
    public func filtered(_ keep: Set<String>) -> PropertyBag {
        PropertyBag(values.filter { keep.contains($0.key) })
    }

    /// Removes keys that are noise for users (driver plumbing, match metadata).
    public func withoutPlumbing() -> PropertyBag {
        PropertyBag(values.filter { !PropertyBag.plumbingKeys.contains($0.key) && !$0.key.hasPrefix("IOFunctionParent") })
    }

    static let plumbingKeys: Set<String> = [
        "IOProbeScore", "IOMatchCategory", "IOMatchedAtBoot", "IOPersonalityPublisher", "IOUserClientClass",
        "IOGeneralInterest", "IOProviderClass", "IONameMatch", "IONameMatched", "CFBundleIdentifier",
        "CFBundleIdentifierKernel", "AutoMatched", "IOClass", "IOCFPlugInTypes", "IOServiceDEXTEntitlements",
        "IOPowerManagement",
    ]
}
