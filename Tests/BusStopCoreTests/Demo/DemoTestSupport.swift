import Foundation
@testable import BusStopCore

/// Shared helpers for the demo scenario tests.
enum DemoTestSupport {
    /// A capture time with whole seconds, so ISO-8601 JSON round-trips exactly.
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    /// The scenario's snapshot, built the way the app builds demo data.
    static func snapshot(_ scenario: DemoScenario, tick: Int = 0) -> HostSnapshot {
        TopologyBuilder.build(scenario.raw(at: date, tick: tick), options: BuildOptions(isDemo: true))
    }

    /// Every device in a snapshot keyed by name; the first of several
    /// equally named devices wins.
    static func devices(_ snapshot: HostSnapshot) -> [String: DeviceNode] {
        var result: [String: DeviceNode] = [:]
        for entry in snapshot.allDevices where result[entry.device.name] == nil {
            result[entry.device.name] = entry.device
        }
        return result
    }

    static func port(_ snapshot: HostSnapshot, _ type: Int, _ number: Int) -> PhysicalPort? {
        snapshot.port(PortKey(type: type, number: number))
    }

    /// True when `value` is within `fraction` of `base`, plus one unit for rounding.
    static func isNear(_ value: Int?, _ base: Double, within fraction: Double) -> Bool {
        guard let value else { return false }
        return abs(Double(value) - base) <= base * fraction + 1
    }

    /// The snapshot without the readings demo mode varies from tick to tick
    /// (port power, system power flow and the battery's power), for
    /// comparing everything else.
    static func withoutPowerReadings(_ snapshot: HostSnapshot) -> HostSnapshot {
        var copy = snapshot
        for i in copy.ports.indices { copy.ports[i].power = nil }
        copy.power.systemInputMilliwatts = nil
        copy.power.systemLoadMilliwatts = nil
        copy.power.portOutputMilliwatts = 0
        copy.power.battery?.powerMilliwatts = nil
        return copy
    }
}
