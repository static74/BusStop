import Foundation

/// The "identify this port" check: the user plugs something into (or out of)
/// one port, and the port whose state changed is the one they mean.
public enum PortIdentification {
    /// The one port whose connection, active transports or devices differ
    /// between the two snapshots. Nil when no port changed, or when several
    /// did and the answer would be a guess.
    public static func changedPort(from before: HostSnapshot, to after: HostSnapshot) -> PortKey? {
        let changed = changedPorts(from: before, to: after)
        return changed.count == 1 ? changed[0] : nil
    }

    /// Every port whose connection, active transports or devices differ.
    public static func changedPorts(from before: HostSnapshot, to after: HostSnapshot) -> [PortKey] {
        after.ports.filter { port in
            guard let old = before.port(port.key) else { return false }
            return state(of: old) != state(of: port)
        }.map(\.key)
    }

    struct PortState: Equatable {
        var isConnected: Bool
        var transports: Set<TransportKind>
        var devices: Set<String>
    }

    static func state(of port: PhysicalPort) -> PortState {
        PortState(isConnected: port.isConnected,
                  transports: Set(port.activeTransports.filter(\.isActive).map(\.kind)),
                  devices: Set(port.allDevices.map(\.device.id)))
    }

    /// This Mac's ports as a PortScope `MacPortLocations.json` entry, in the
    /// snapshot's port order, with each port's current name as its location.
    /// Ports without a name are left out, and so are ports placed only by
    /// rank, whose location is a guess. Built locally for the user to copy;
    /// nothing is sent anywhere.
    public static func catalogEntry(for snapshot: HostSnapshot) throws -> String {
        let model = snapshot.machine.model
        let ports = snapshot.ports.compactMap { port -> CatalogPort? in
            guard port.kind != .unknown, port.label.source != .catalogRank,
                  let location = port.label.location else { return nil }
            // PortScope spells the SD slot "sd-card"; see scripts/generate-port-catalog.py.
            let connector = port.kind == .sdCard ? "sd-card" : port.kind.catalogConnector
            return CatalogPort(connector: connector, port_number: port.number, location: location,
                               capability: port.capabilityDescription)
        }
        let entry = CatalogModel(marketing_name: snapshot.machine.name,
                                 chassis: PortLocationCatalog.entry(for: model)?.chassis, ports: ports)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode([model: entry]), as: UTF8.self)
    }

    // Field names follow PortScope's JSON.
    struct CatalogModel: Encodable {
        var marketing_name: String
        var chassis: String?
        var ports: [CatalogPort]
    }

    struct CatalogPort: Encodable {
        var connector: String
        var port_number: Int
        var location: String
        var capability: String?
    }
}
