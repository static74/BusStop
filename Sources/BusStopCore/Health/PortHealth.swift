import Foundation

/// One port's last 7 local calendar days, from the history archive (SPEC
/// §5.4, "Port health"). All-time totals stay the hardware counters in
/// `PhysicalPort.statistics`.
public struct PortHealth: Sendable, Hashable {
    public var plugEvents = 0
    public var connections = 0
    public var overcurrents = 0
    public var liquidDetections = 0
    /// Connections that ended within `shortConnection`, slower links and USB 2
    /// fallbacks in the event log. A slowdown and the USB 2 fallback it raises
    /// in the same capture count once.
    public var errors = 0
    /// The capture that saw the last overcurrent increase, at any age.
    public var lastOvercurrentAt: Date?

    public init() {}

    /// A device that leaves this soon after connecting counts as a connection error.
    public static let shortConnection: TimeInterval = 10
}

extension HistoryArchive {
    /// Port health for one Mac model over the 7 local days ending with the
    /// day of `now`, keyed by port. Ports with nothing on record are left out.
    public func portHealth(model: String, now: Date, calendar: Calendar = .current) -> [PortKey: PortHealth] {
        guard let section = sections[model] else { return [:] }
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        var result: [PortKey: PortHealth] = [:]

        for (key, days) in section.portDays {
            guard let port = PortKey(key) else { continue }
            for day in days where day.day >= start {
                result[port, default: PortHealth()].plugEvents += day.plugEvents
                result[port, default: PortHealth()].connections += day.connections
                result[port, default: PortHealth()].overcurrents += day.overcurrents
                result[port, default: PortHealth()].liquidDetections += day.liquidDetections
            }
        }
        for (key, date) in section.lastOvercurrentAt {
            guard let port = PortKey(key) else { continue }
            result[port, default: PortHealth()].lastOvercurrentAt = date
        }

        // Oldest first, so a connect is seen before the disconnect that ends it.
        var connectedAt: [String: (date: Date, port: PortKey)] = [:]
        var slowdowns = Set<String>()
        for event in section.events.reversed() where event.date >= start {
            let subject = event.subjectID ?? event.deviceID ?? event.id
            switch event.kind {
            case .deviceConnected:
                if let port = event.portKey { connectedAt[subject] = (event.date, port) }
            case .deviceDisconnected:
                if let connect = connectedAt.removeValue(forKey: subject),
                   event.date.timeIntervalSince(connect.date) < PortHealth.shortConnection {
                    result[connect.port, default: PortHealth()].errors += 1
                }
            case .linkChanged, .diagnosticRaised:
                let isSlowdown = event.kind == .linkChanged
                    ? event.isDowngrade : subject.hasPrefix("\(DiagnosticKind.usb2Fallback.rawValue):")
                // The fallback finding a slowdown raises carries the same device and date.
                guard isSlowdown, let port = event.portKey,
                      slowdowns.insert("\(event.date.timeIntervalSince1970)|\(event.deviceID ?? subject)").inserted
                else { break }
                result[port, default: PortHealth()].errors += 1
            default:
                break
            }
        }
        return result
    }
}
