import Foundation

/// Something that changed between two snapshots.
public struct ConnectionEvent: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Hashable, Codable, CaseIterable {
        case deviceConnected
        case deviceDisconnected
        /// A device or port link got faster or slower.
        case linkChanged
        case chargerConnected
        case chargerDisconnected
        case displayConnected
        case displayDisconnected
        case diagnosticRaised
    }

    public var id: String
    public var date: Date
    public var kind: Kind
    /// "Samsung T9 connected"
    public var title: String
    /// "Left Front · USB-C · USB 3.2 Gen 2 @ 10 Gb/s"
    public var detail: String
    public var portKey: PortKey?
    public var deviceID: String?
    /// For `.linkChanged`: true when the new link is slower.
    public var isDowngrade: Bool

    public init(id: String, date: Date, kind: Kind, title: String, detail: String, portKey: PortKey? = nil,
                deviceID: String? = nil, isDowngrade: Bool = false) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.detail = detail
        self.portKey = portKey
        self.deviceID = deviceID
        self.isDowngrade = isDowngrade
    }

    public var symbolName: String {
        switch kind {
        case .deviceConnected: return "arrow.down.right.circle.fill"
        case .deviceDisconnected: return "arrow.up.left.circle"
        case .linkChanged: return isDowngrade ? "arrow.down.circle" : "arrow.up.circle"
        case .chargerConnected: return "bolt.circle.fill"
        case .chargerDisconnected: return "bolt.slash.circle"
        case .displayConnected: return "display"
        case .displayDisconnected: return "display.trianglebadge.exclamationmark"
        case .diagnosticRaised: return "exclamationmark.triangle"
        }
    }
}
