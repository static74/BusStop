import BusStopCore
import Foundation

/// Decides when `PortStore` rewrites the widget payload: at once when what the
/// widgets show changes, at most once a minute when only the power moves (in
/// whole watts), and every few minutes regardless, since a payload older than
/// `WidgetTimeline.staleAfter` reads as "Bus Stop isn't running".
struct WidgetWriteGate {
    static let powerInterval: TimeInterval = 60
    static let heartbeat: TimeInterval = 4 * 60

    private var lastContent: Content?
    private var lastPower: PowerSample?
    private var lastWrite = Date.distantPast

    /// What the widgets show, apart from the power readings.
    private struct Content: Equatable {
        var snapshot: HostSnapshot
        var events: ArraySlice<ConnectionEvent>
        var portHealth: [PortKey: PortHealth]
    }

    /// True when a write is due; it then counts as written at `now`.
    mutating func shouldWrite(_ snapshot: HostSnapshot, events: [ConnectionEvent],
                              portHealth: [PortKey: PortHealth], now: Date) -> Bool {
        let content = Content(snapshot: Self.withoutPowerReadings(snapshot),
                              events: events.prefix(WidgetPayload.eventLimit), portHealth: portHealth)
        let power = Self.wholeWatts(PowerSample(snapshot))
        let sinceWrite = now.timeIntervalSince(lastWrite)
        guard content != lastContent
                || (power != lastPower && sinceWrite >= Self.powerInterval)
                || sinceWrite >= Self.heartbeat
                // A clock set back must not hold writes off for good.
                || sinceWrite < 0 else { return false }
        lastContent = content
        lastPower = power
        lastWrite = now
        return true
    }

    /// Forgets the last write, so the next capture writes again.
    mutating func reset() {
        self = WidgetWriteGate()
    }

    private static func withoutPowerReadings(_ snapshot: HostSnapshot) -> HostSnapshot {
        var copy = snapshot
        copy.capturedAt = .distantPast
        for i in copy.ports.indices { copy.ports[i].power = nil }
        copy.power.systemInputMilliwatts = nil
        copy.power.systemLoadMilliwatts = nil
        copy.power.portOutputMilliwatts = 0
        copy.power.battery?.powerMilliwatts = nil
        return copy
    }

    private static func wholeWatts(_ sample: PowerSample) -> PowerSample {
        func round(_ milliwatts: Int?) -> Int? { milliwatts.map { Int((Double($0) / 1000).rounded()) } }
        return PowerSample(date: .distantPast, systemInputMilliwatts: round(sample.systemInputMilliwatts),
                           batteryMilliwatts: round(sample.batteryMilliwatts),
                           systemLoadMilliwatts: round(sample.systemLoadMilliwatts),
                           portMilliwatts: sample.portMilliwatts.compactMapValues { round($0) })
    }
}
