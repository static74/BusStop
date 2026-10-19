import Foundation

/// Everything Bus Stop remembers between launches, one section per Mac model
/// (`hw.model`): the event log, power averaged per minute, and per-port
/// counter increases per local day. Pure data; the app reads and writes the
/// file (SPEC §5.6).
public struct HistoryArchive: Sendable, Hashable, Codable {
    public static let schemaVersion = 1
    public static let maxEvents = 5_000
    public static let eventAge: TimeInterval = 30 * 86_400
    public static let powerAge: TimeInterval = 7 * 86_400
    public static let portDayAge: TimeInterval = 90 * 86_400
    public static let maxBytes = 5_000_000

    public var schemaVersion: Int
    /// Keyed by `hw.model`.
    public var sections: [String: Section]

    /// One Mac model's history.
    public struct Section: Sendable, Hashable, Codable {
        /// Newest first, unique ids.
        public var events: [ConnectionEvent] = []
        /// Oldest first, one per minute that had a sample.
        public var power: [PowerBucket] = []
        /// Samples of the minute in progress.
        public var pendingPower: [PowerSample] = []
        /// `PortKey.description` → days with a counter increase, oldest first.
        public var portDays: [String: [PortDay]] = [:]
        /// The counters at the last capture, to take the next delta from.
        public var lastCounters: [String: PortStatistics] = [:]
        public var lastLiquid: [String: Bool] = [:]
        /// `PortKey.description` → the capture that saw the last overcurrent increase.
        public var lastOvercurrentAt: [String: Date] = [:]
        public var lastCaptureAt: Date?

        public init() {}
    }

    /// Average power over one minute.
    public struct PowerBucket: Sendable, Hashable, Codable {
        public var start: Date
        public var systemInputMilliwatts: Int?
        public var batteryMilliwatts: Int?
        public var systemLoadMilliwatts: Int?
        /// Keyed by `PortKey.description`; positive = out of the Mac.
        public var portMilliwatts: [String: Int]

        public init(start: Date, systemInputMilliwatts: Int? = nil, batteryMilliwatts: Int? = nil,
                    systemLoadMilliwatts: Int? = nil, portMilliwatts: [String: Int] = [:]) {
            self.start = start
            self.systemInputMilliwatts = systemInputMilliwatts
            self.batteryMilliwatts = batteryMilliwatts
            self.systemLoadMilliwatts = systemLoadMilliwatts
            self.portMilliwatts = portMilliwatts
        }

        enum CodingKeys: String, CodingKey {
            case start = "t", systemInputMilliwatts = "in", batteryMilliwatts = "bat", systemLoadMilliwatts = "load"
            case portMilliwatts = "ports"
        }
    }

    /// Counter increases on one port during one local calendar day, so "the
    /// last 7 days" means the user's days.
    public struct PortDay: Sendable, Hashable, Codable {
        /// Start of the local day.
        public var day: Date
        public var plugEvents = 0
        public var connections = 0
        public var overcurrents = 0
        public var liquidDetections = 0

        public init(day: Date) { self.day = day }

        var isEmpty: Bool { plugEvents == 0 && connections == 0 && overcurrents == 0 && liquidDetections == 0 }
    }

    /// How much is kept, for Settings.
    public struct Summary: Sendable, Hashable {
        public var eventCount: Int
        public var oldest: Date?

        public init(eventCount: Int = 0, oldest: Date? = nil) {
            self.eventCount = eventCount
            self.oldest = oldest
        }
    }

    public init() {
        schemaVersion = Self.schemaVersion
        sections = [:]
    }

    // MARK: Recording

    /// Folds one capture in: its power sample (a finished minute becomes a
    /// bucket), counter increases and liquid detections since the last
    /// capture, and the time of the last overcurrent increase.
    ///
    /// `afterGap` is true for the first capture after launch, wake or a
    /// change of source: nothing is counted across it, since the counters may
    /// have moved while Bus Stop was not watching. A counter that goes down
    /// starts a new epoch and counts nothing. A capture dated before the last
    /// one (the clock was set back) counts as after a gap and its power sample
    /// is dropped; nothing else is lost. Pass each capture once.
    public mutating func record(_ snapshot: HostSnapshot, afterGap: Bool, calendar: Calendar = .current) {
        // Mutated in place, so the section's long lists are not copied on every capture.
        sections[snapshot.machine.model, default: Section()].record(snapshot, afterGap: afterGap, calendar: calendar)
    }

    /// The increase from `old` to `new`; zero when either is unknown or the
    /// counter went down (a new epoch).
    static func delta(_ old: Int?, _ new: Int?) -> Int {
        guard let old, let new, new > old else { return 0 }
        return new - old
    }

    /// Adds `events` (in the order they happened, as `SnapshotDiffer` returns
    /// them) newest first, skipping ids already kept.
    public mutating func append(_ events: [ConnectionEvent], model: String) {
        guard !events.isEmpty else { return }
        var seen = Set(self.events(model: model).map(\.id))
        let fresh = events.filter { seen.insert($0.id).inserted }
        sections[model, default: Section()].events.insert(contentsOf: fresh.reversed(), at: 0)
        sections[model]?.trimCount()
    }

    /// The event log for one Mac model, newest first.
    public func events(model: String) -> [ConnectionEvent] { sections[model]?.events ?? [] }

    public mutating func clearEvents(model: String) { sections[model]?.events.removeAll() }

    /// Applies the age caps to every section, including models not seen this session.
    public mutating func trim(now: Date) {
        for model in sections.keys { sections[model]?.trim(now: now) }
    }

    /// Events kept and the oldest thing kept, over every section.
    public var summary: Summary {
        var result = Summary()
        for section in sections.values {
            result.eventCount += section.events.count
            let dates = [section.events.last?.date, section.power.first?.start, section.pendingPower.first?.date]
                + section.portDays.values.map { $0.first?.day }
            for date in dates.compactMap({ $0 }) where date < (result.oldest ?? .distantFuture) {
                result.oldest = date
            }
        }
        return result
    }

    // MARK: Codec

    public enum DecodeError: Error, Equatable {
        /// Not a history file, or cut short.
        case corrupt
        /// Written by a newer Bus Stop; must not be overwritten.
        case newerSchema(Int)
    }

    /// Reads a history file. An entry that does not decode (an event kind from
    /// a newer version, say) is dropped on its own, not the whole file.
    public static func decode(_ data: Data) throws(DecodeError) -> HistoryArchive {
        struct Header: Decodable { var schemaVersion: Int }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data) else { throw .corrupt }
        guard header.schemaVersion <= schemaVersion else { throw .newerSchema(header.schemaVersion) }
        guard let archive = try? decoder.decode(HistoryArchive.self, from: data) else { throw .corrupt }
        return archive
    }

    /// The archive as JSON no larger than `maxBytes`, dropping the oldest
    /// events, power minutes and port days until it fits. Dates are encoded as
    /// plain numbers, never ISO 8601, which would drop the milliseconds that
    /// event ids carry.
    public func encoded(maxBytes: Int = maxBytes) throws -> Data {
        let encoder = JSONEncoder()
        var copy = self
        var data = try encoder.encode(copy)
        while data.count > maxBytes {
            // Shrink every list by the overshoot plus a margin, oldest entries first.
            let keep = Double(maxBytes) / Double(data.count) * 0.9
            var dropped = false
            for model in copy.sections.keys {
                dropped = copy.sections[model]!.dropOldest(keeping: keep) || dropped
            }
            guard dropped else { break }
            data = try encoder.encode(copy)
        }
        return data
    }
}

extension HistoryArchive.Section {
    /// Keys spelled out so `init(from:)` can decode lists entry by entry.
    enum CodingKeys: String, CodingKey {
        case events, power, pendingPower, portDays, lastCounters, lastLiquid, lastOvercurrentAt, lastCaptureAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events = try c.decodeIfPresent(LossyList<ConnectionEvent>.self, forKey: .events)?.elements ?? []
        power = try c.decodeIfPresent(LossyList<HistoryArchive.PowerBucket>.self, forKey: .power)?.elements ?? []
        pendingPower = try c.decodeIfPresent(LossyList<PowerSample>.self, forKey: .pendingPower)?.elements ?? []
        portDays = try c.decodeIfPresent([String: LossyList<HistoryArchive.PortDay>].self, forKey: .portDays)?
            .mapValues(\.elements) ?? [:]
        lastCounters = try c.decodeIfPresent([String: PortStatistics].self, forKey: .lastCounters) ?? [:]
        lastLiquid = try c.decodeIfPresent([String: Bool].self, forKey: .lastLiquid) ?? [:]
        lastOvercurrentAt = try c.decodeIfPresent([String: Date].self, forKey: .lastOvercurrentAt) ?? [:]
        lastCaptureAt = try c.decodeIfPresent(Date.self, forKey: .lastCaptureAt)
    }

    mutating func record(_ snapshot: HostSnapshot, afterGap: Bool, calendar: Calendar) {
        let date = snapshot.capturedAt
        let gap = afterGap || date < (lastCaptureAt ?? .distantPast)
        lastCaptureAt = date

        addPower(PowerSample(snapshot))

        let day = calendar.startOfDay(for: date)
        for port in snapshot.ports {
            let key = port.id
            var change = HistoryArchive.PortDay(day: day)
            if let stats = port.statistics {
                if !gap, let last = lastCounters[key] {
                    change.plugEvents = HistoryArchive.delta(last.plugEventCount, stats.plugEventCount)
                    change.connections = HistoryArchive.delta(last.connectionCount, stats.connectionCount)
                    change.overcurrents = HistoryArchive.delta(last.overcurrentCount, stats.overcurrentCount)
                }
                lastCounters[key] = stats
            }
            if !gap, port.liquidDetected, lastLiquid[key] == false { change.liquidDetections = 1 }
            lastLiquid[key] = port.liquidDetected
            if change.overcurrents > 0 { lastOvercurrentAt[key] = date }
            if !change.isEmpty { add(change, port: key) }
        }
        trim(now: date)
    }

    /// Adds a sample to the minute in progress, closing that minute into a
    /// bucket when the sample starts a new one. A sample older than what is
    /// already kept is dropped.
    mutating func addPower(_ sample: PowerSample) {
        let minute = Date(timeIntervalSinceReferenceDate:
            (sample.date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        if let last = power.last, minute <= last.start { return }
        if let last = pendingPower.last {
            if sample.date < last.date { return }
            // The sample's minute starts after the last pending sample: that minute is over.
            if minute > last.date { closePendingMinute() }
        }
        pendingPower.append(sample)
    }

    mutating func closePendingMinute() {
        guard let first = pendingPower.first else { return }
        func average(_ values: [Int]) -> Int? {
            values.isEmpty ? nil : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        }
        var ports: [String: Int] = [:]
        for key in Set(pendingPower.flatMap(\.portMilliwatts.keys)) {
            ports[key] = average(pendingPower.compactMap { $0.portMilliwatts[key] })
        }
        power.append(HistoryArchive.PowerBucket(
            start: Date(timeIntervalSinceReferenceDate: (first.date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60),
            systemInputMilliwatts: average(pendingPower.compactMap(\.systemInputMilliwatts)),
            batteryMilliwatts: average(pendingPower.compactMap(\.batteryMilliwatts)),
            systemLoadMilliwatts: average(pendingPower.compactMap(\.systemLoadMilliwatts)),
            portMilliwatts: ports))
        pendingPower.removeAll()
    }

    mutating func add(_ change: HistoryArchive.PortDay, port key: String) {
        var days = portDays[key] ?? []
        if let i = days.lastIndex(where: { $0.day == change.day }) {
            days[i].plugEvents += change.plugEvents
            days[i].connections += change.connections
            days[i].overcurrents += change.overcurrents
            days[i].liquidDetections += change.liquidDetections
        } else {
            days.append(change)
            days.sort { $0.day < $1.day }
        }
        portDays[key] = days
    }

    /// Drops what is older than the caps allow, and events beyond the count cap.
    mutating func trim(now: Date) {
        let eventCutoff = now.addingTimeInterval(-HistoryArchive.eventAge)
        if let oldest = events.last, oldest.date < eventCutoff { events.removeAll { $0.date < eventCutoff } }
        trimCount()
        let powerCutoff = now.addingTimeInterval(-HistoryArchive.powerAge)
        if let first = power.first, first.start < powerCutoff { power.removeAll { $0.start < powerCutoff } }
        let dayCutoff = now.addingTimeInterval(-HistoryArchive.portDayAge)
        for (key, days) in portDays where days.first.map({ $0.day < dayCutoff }) == true {
            let kept = days.filter { $0.day >= dayCutoff }
            portDays[key] = kept.isEmpty ? nil : kept
        }
    }

    mutating func trimCount() {
        if events.count > HistoryArchive.maxEvents { events.removeLast(events.count - HistoryArchive.maxEvents) }
    }

    /// Keeps the newest `fraction` of events, power minutes and each port's
    /// days. Returns false when there was nothing left to drop.
    mutating func dropOldest(keeping fraction: Double) -> Bool {
        func dropCount(_ count: Int) -> Int { count - Int(Double(count) * fraction) }
        let eventDrop = dropCount(events.count)
        let powerDrop = dropCount(power.count)
        events.removeLast(eventDrop)
        power.removeFirst(powerDrop)
        var dropped = eventDrop + powerDrop > 0
        for (key, days) in portDays {
            let drop = dropCount(days.count)
            guard drop > 0 else { continue }
            dropped = true
            portDays[key] = drop == days.count ? nil : Array(days.dropFirst(drop))
        }
        return dropped
    }
}

/// A JSON array decoded entry by entry: an entry that fails to decode is
/// skipped instead of failing the whole list.
private struct LossyList<Element: Decodable>: Decodable {
    var elements: [Element] = []

    /// Decodes nothing, so a bad entry can be stepped over.
    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode does not move the container on; this does.
                _ = try container.decode(Skip.self)
            }
        }
    }
}
