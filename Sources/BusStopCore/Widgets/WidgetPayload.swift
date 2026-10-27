import Foundation

/// Everything the desktop widgets show, written by the app into the App Group
/// container. The widget extension never reads hardware (its sandbox blocks the
/// SMC and parts of IOKit), so it only decodes this.
///
/// Built redacted: the snapshot and events go through `Exporter.redacted`, and
/// raw property bags are left out, so the file holds no serial numbers. Events
/// and diagnostics can name devices that are no longer connected, so `serials`
/// takes the serial numbers seen before: this session's and the history's
/// (`HistoryArchive.serials(model:)`).
public struct WidgetPayload: Sendable, Hashable, Codable {
    /// Raised when a change means an older extension can no longer read the file.
    public static let currentSchemaVersion = 1
    /// How many of the newest events the payload carries.
    public static let eventLimit = 20
    /// The day chart's resolution.
    public static let dayPowerStep: TimeInterval = 5 * 60
    public static let dayPowerSpan: TimeInterval = 24 * 60 * 60

    public var schemaVersion: Int
    /// When the snapshot was captured; the widgets go stale 5 minutes after it.
    public var capturedAt: Date
    public var isDemo: Bool
    /// Redacted, without raw property bags.
    public var snapshot: HostSnapshot
    /// The in-memory last 10 minutes (`PowerHistory`), oldest first.
    public var recentPower: [PowerSample]
    /// The last 24 hours at `dayPowerStep`, from `HistoryArchive.powerSamples`, oldest first.
    public var dayPower: [PowerSample]
    /// Newest first, at most `eventLimit`, redacted.
    public var events: [ConnectionEvent]
    /// Each port's last 7 days, as `HistoryArchive.portHealth` gives it.
    public var portHealth: [PortKey: PortHealth]
    /// The same 7 days one by one, oldest first, as `HistoryArchive.dailyPortHealth` gives
    /// them, for the Health widget's strip. Nil when the user keeps no history.
    public var portDays: [PortKey: [PortHealth]]?

    public init(snapshot: HostSnapshot, recentPower: [PowerSample] = [], dayPower: [PowerSample] = [],
                events: [ConnectionEvent] = [], portHealth: [PortKey: PortHealth] = [:],
                portDays: [PortKey: [PortHealth]]? = nil, serials: Set<String> = []) {
        schemaVersion = Self.currentSchemaVersion
        capturedAt = snapshot.capturedAt
        isDemo = snapshot.isDemo
        self.snapshot = Self.withoutProperties(Exporter.redacted(snapshot, serials: serials))
        self.recentPower = recentPower
        self.dayPower = dayPower
        let textSerials = serials.union(Exporter.serialStrings(in: snapshot)).filter(Exporter.isTextSerial)
        self.events = events.prefix(Self.eventLimit).map { Exporter.redacted($0, textSerials: textSerials) }
        self.portHealth = portHealth
        self.portDays = portDays
    }

    /// The snapshot without the raw IORegistry properties the inspector shows.
    static func withoutProperties(_ snapshot: HostSnapshot) -> HostSnapshot {
        func strip(_ device: DeviceNode) -> DeviceNode {
            var device = device
            device.properties = nil
            device.children = device.children.map(strip)
            device.internalParts = device.internalParts?.map(strip)
            return device
        }
        var copy = snapshot
        for i in copy.ports.indices {
            copy.ports[i].properties = nil
            copy.ports[i].devices = copy.ports[i].devices.map(strip)
        }
        copy.otherDevices = copy.otherDevices.map(strip)
        return copy
    }
}
