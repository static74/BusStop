import Foundation

/// Options that change how a `RawSnapshot` is interpreted.
public struct BuildOptions: Sendable, Hashable {
    /// Port key (`"2/1"`) → user-chosen port name.
    public var userPortNames: [String: String]
    /// Copy raw IORegistry properties onto ports and devices for the inspector.
    public var includeRawProperties: Bool
    /// Mark the result as demo data.
    public var isDemo: Bool

    public init(userPortNames: [String: String] = [:], includeRawProperties: Bool = true, isDemo: Bool = false) {
        self.userPortNames = userPortNames
        self.includeRawProperties = includeRawProperties
        self.isDemo = isDemo
    }
}

/// Turns raw IORegistry data into the port → device topology.
///
/// Pure and deterministic: the same `RawSnapshot` and options always produce
/// the same `HostSnapshot`. See `docs/SPEC.md` §5.4 for the rules.
public enum TopologyBuilder {
    public static func build(_ raw: RawSnapshot, options: BuildOptions = BuildOptions()) -> HostSnapshot {
        // Implemented in TopologyBuilder+*.swift.
        fatalError("TopologyBuilder.build not implemented")
    }
}
