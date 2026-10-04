import Foundation

/// Resolves human names for ports. See SPEC §5.4 "Labels".
public enum PortLabeler {
    /// Label for one port.
    ///
    /// - Parameters:
    ///   - kind: connector kind of the port.
    ///   - number: IOKit `PortNumber`.
    ///   - key: the port key (for user overrides).
    ///   - siblings: numbers of all ports of the same kind on this Mac (for rank fallback).
    ///   - model: `hw.model`.
    ///   - userNames: port key string → user name.
    public static func label(kind: PortKind, number: Int, key: PortKey, siblings: [Int], model: String,
                             userNames: [String: String]) -> (label: PortLabel, capability: String?) {
        if let name = userNames[key.description], !name.isEmpty {
            return (PortLabel(location: name, source: .user, connector: kind.displayName, number: number), nil)
        }
        return (PortLabel(location: nil, source: .generic, connector: kind.displayName, number: number), nil)
    }

    /// Physical sort order for ports on a model: catalogue order when known,
    /// then by kind rank and number.
    public static func sortKey(kind: PortKind, number: Int, siblings: [Int], model: String) -> (Int, Int, Int) {
        (1, kind.sortRank, number)
    }
}
