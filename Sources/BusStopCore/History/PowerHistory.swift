import Foundation

/// One point in the power history.
public struct PowerSample: Sendable, Hashable, Codable {
    public var date: Date
    /// System input power (mW), when known.
    public var systemInputMilliwatts: Int?
    /// Battery power (mW, + charging), when known.
    public var batteryMilliwatts: Int?
    /// Power the Mac itself is consuming (mW), when known.
    public var systemLoadMilliwatts: Int?
    /// Per-port power (mW) keyed by port key string; positive = out of the Mac, negative = into it.
    public var portMilliwatts: [String: Int]

    public init(date: Date, systemInputMilliwatts: Int? = nil, batteryMilliwatts: Int? = nil,
                systemLoadMilliwatts: Int? = nil, portMilliwatts: [String: Int] = [:]) {
        self.date = date
        self.systemInputMilliwatts = systemInputMilliwatts
        self.batteryMilliwatts = batteryMilliwatts
        self.systemLoadMilliwatts = systemLoadMilliwatts
        self.portMilliwatts = portMilliwatts
    }

    /// The sample a snapshot contributes to the history.
    public init(_ snapshot: HostSnapshot) {
        var ports: [String: Int] = [:]
        for port in snapshot.ports {
            guard let power = port.power, let mw = power.milliwatts else { continue }
            switch power.direction {
            case .output: ports[port.id] = mw
            case .input: ports[port.id] = -mw
            case .none: continue
            }
        }
        self.init(date: snapshot.capturedAt,
                  systemInputMilliwatts: snapshot.power.systemInputMilliwatts,
                  batteryMilliwatts: snapshot.power.battery?.powerMilliwatts,
                  systemLoadMilliwatts: snapshot.power.systemLoadMilliwatts,
                  portMilliwatts: ports)
    }
}

extension PowerSample {
    /// A minute (or longer window) of saved power, dated at its start.
    public init(_ bucket: HistoryArchive.PowerBucket) {
        self.init(date: bucket.start, systemInputMilliwatts: bucket.systemInputMilliwatts,
                  batteryMilliwatts: bucket.batteryMilliwatts, systemLoadMilliwatts: bucket.systemLoadMilliwatts,
                  portMilliwatts: bucket.portMilliwatts)
    }

    /// A line segment number for each date (oldest first): a new segment
    /// starts after a gap longer than `maxGap`, so a chart does not draw a
    /// line across sleep or the time Bus Stop was not running.
    public static func segments(_ dates: [Date], maxGap: TimeInterval) -> [Int] {
        var segment = 0
        return dates.indices.map { index in
            if index > 0, dates[index].timeIntervalSince(dates[index - 1]) > maxGap { segment += 1 }
            return segment
        }
    }
}

/// Chart series from a run of samples, oldest first: the live buffer's or
/// the saved history's.
extension Collection where Element == PowerSample {
    /// System input series as (date, watts) pairs.
    public var systemInputSeries: [(date: Date, watts: Double)] {
        compactMap { sample in
            sample.systemInputMilliwatts.map { (sample.date, Double($0) / 1000) }
        }
    }

    /// Battery series as (date, watts) pairs; positive while charging.
    public var batterySeries: [(date: Date, watts: Double)] {
        compactMap { sample in
            sample.batteryMilliwatts.map { (sample.date, Double($0) / 1000) }
        }
    }

    /// System load series as (date, watts) pairs.
    public var systemLoadSeries: [(date: Date, watts: Double)] {
        compactMap { sample in
            sample.systemLoadMilliwatts.map { (sample.date, Double($0) / 1000) }
        }
    }

    /// Series for one port as (date, watts); absent samples are skipped.
    /// Positive values are power out of the Mac, negative values power in.
    public func series(for key: PortKey) -> [(date: Date, watts: Double)] {
        let id = key.description
        return compactMap { sample in
            sample.portMilliwatts[id].map { (sample.date, Double($0) / 1000) }
        }
    }

    /// Keys of every port that appears in the history.
    public var portKeys: [PortKey] {
        Set(flatMap(\.portMilliwatts.keys)).compactMap(PortKey.init).sorted()
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
        self.capacity = max(1, capacity)
        self.samples = []
    }

    /// Appends a sample derived from `snapshot` (dated `snapshot.capturedAt`).
    /// Samples closer than 0.5 s to the previous one replace it.
    public mutating func append(_ snapshot: HostSnapshot) {
        append(PowerSample(snapshot))
    }

    public mutating func append(_ sample: PowerSample) {
        if let last = samples.last {
            if sample.date < last.date {
                // Clock went backwards (or demo restarted): start over.
                samples.removeAll()
            } else if sample.date.timeIntervalSince(last.date) < 0.5 {
                samples.removeLast()
            }
        }
        samples.append(sample)
        let cutoff = sample.date.addingTimeInterval(-window)
        if let firstKept = samples.firstIndex(where: { $0.date >= cutoff }), firstKept > 0 {
            samples.removeFirst(firstKept)
        }
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    public mutating func removeAll() { samples.removeAll() }
}
