import Foundation

/// One port's last 7 local calendar days, from the history archive (SPEC
/// §5.4, "Port health"). All-time totals stay the hardware counters in
/// `PhysicalPort.statistics`.
public struct PortHealth: Sendable, Hashable {
    public var plugEvents = 0
    public var connections = 0
    public var overcurrents = 0
    public var liquidDetections = 0
    /// Connections that ended within `shortConnection` on the port they
    /// started on, slower USB and Thunderbolt links and USB 2 fallbacks in the event log. A
    /// slowdown and the USB 2 fallback it raises in the same capture count
    /// once, and a device's fallback counts once per port, since it comes back
    /// on every plug-in when the cable is the cause.
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
        var fallbacks = Set<String>()
        let fallbackPrefix = "\(DiagnosticKind.usb2Fallback.rawValue):"
        // A connect just before the window still makes a short connection that ends inside it.
        let connectStart = start.addingTimeInterval(-PortHealth.shortConnection)
        for event in section.events.reversed()
        where event.date >= start || (event.kind == .deviceConnected && event.date >= connectStart) {
            let subject = event.subjectID ?? event.deviceID ?? event.id
            switch event.kind {
            case .deviceConnected:
                if let port = event.portKey { connectedAt[subject] = (event.date, port) }
            case .deviceDisconnected:
                // A device that moved ports raised no events, so the disconnect can be on another port.
                // A negative time means the clock was set back in between, not a short connection.
                if let connect = connectedAt.removeValue(forKey: subject), event.portKey == connect.port,
                   (0..<PortHealth.shortConnection).contains(event.date.timeIntervalSince(connect.date)) {
                    result[connect.port, default: PortHealth()].errors += 1
                }
            case .linkChanged, .diagnosticRaised:
                // DisplayPort retrains on mode changes and wake, as in `ConnectionHealth`.
                guard !subject.hasPrefix("display:") else { break }
                let isFallback = event.kind == .diagnosticRaised && subject.hasPrefix(fallbackPrefix)
                guard event.kind == .linkChanged ? event.isDowngrade : isFallback, let port = event.portKey
                else { break }
                // The device, not the dock its part is built into: a slowdown's subject, a fallback's id suffix.
                let device = isFallback ? String(subject.dropFirst(fallbackPrefix.count)) : subject
                // The fallback a slowdown raises carries the same device and date.
                let newCapture = slowdowns.insert("\(event.date.timeIntervalSince1970)|\(device)").inserted
                let newFallback = !isFallback || fallbacks.insert("\(port)|\(device)").inserted
                guard newCapture, newFallback else { break }
                result[port, default: PortHealth()].errors += 1
            default:
                break
            }
        }
        return result
    }
}
