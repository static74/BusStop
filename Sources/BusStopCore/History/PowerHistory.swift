import Foundation

/// One point in the power history.
public struct PowerSample: Sendable, Hashable, Codable {
    public var date: Date
    /// System input power (mW), when known.
    public var systemInputMilliwatts: Int?
    /// Battery power (mW, + charging), when known.
    public var batteryMilliwatts: Int?
    /// Per-port power (mW) keyed by port key string; positive = out of the Mac, negative = into it.
    public var portMilliwatts: [String: Int]

    public init(date: Date, systemInputMilliwatts: Int? = nil, batteryMilliwatts: Int? = nil, portMilliwatts: [String: Int] = [:]) {
        self.date = date
        self.systemInputMilliwatts = systemInputMilliwatts
        self.batteryMilliwatts = batteryMilliwatts
        self.portMilliwatts = portMilliwatts
    }
}

/// A fixed-window ring buffer of power samples.
public struct PowerHistory: Sendable, Hashable {
    /// Samples older than this (relative to the newest) are dropped.
    public var window: TimeInterval
    /// Hard cap on stored samples.
    public var capacity: Int
    public private(set) var samples: [PowerSample]

    public init(window: TimeInterval = 600, capacity: Int = 600) {
        self.window = window
        self.capacity = capacity
        self.samples = []
    }

    /// Appends a sample derived from `snapshot` (dated `snapshot.capturedAt`).
    /// Samples closer than 0.5 s to the previous one replace it.
    public mutating func append(_ snapshot: HostSnapshot) {
        fatalError("not implemented")
    }

    public mutating func append(_ sample: PowerSample) {
        fatalError("not implemented")
    }

    /// System input series as (date, watts) pairs.
    public var systemInputSeries: [(date: Date, watts: Double)] {
        fatalError("not implemented")
    }

    /// Series for one port as (date, watts); absent samples are skipped.
    public func series(for key: PortKey) -> [(date: Date, watts: Double)] {
        fatalError("not implemented")
    }

    public mutating func removeAll() { samples.removeAll() }
}
