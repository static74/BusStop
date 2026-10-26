import BusStopCore
import Foundation

/// What the Health widget shows, worked out from the payload so the views
/// only lay it out.
public struct HealthWidgetModel: Sendable {
    /// Most severe first; within a severity, connection-health findings
    /// (`PopoverText.healthKinds`) before the rest, then by title.
    public var findings: [Diagnostic]
    /// Newest first.
    public var events: [ConnectionEvent]
    /// One row per port in physical order; nil when the user keeps no history.
    public var strip: [PortWeek]?
    /// The start of each day the strip covers, oldest first; the last is the day of the capture.
    public var days: [Date]
    /// "Last 7 days: 24 connections · 2 problems"; nil when the user keeps no history.
    public var week: String?

    /// How one port did on one day, worst first.
    public enum Day: Sendable, Hashable {
        /// An overcurrent or liquid in the port.
        case critical
        /// A short connection, a slowdown or a USB 2 fallback.
        case problems
        case used
        case quiet
    }

    /// One port's row in the 7-day strip.
    public struct PortWeek: Sendable, Hashable, Identifiable {
        public var key: PortKey
        /// "Left Front".
        public var title: String
        /// "USB-C".
        public var connector: String
        /// Oldest first, one per day in `HealthWidgetModel.days`.
        public var days: [Day]
        /// "12 connections", "2 problems", "Overcurrent".
        public var summary: String
        public var id: PortKey { key }
    }

    public init(_ payload: WidgetPayload, calendar: Calendar = .current) {
        findings = payload.snapshot.diagnostics.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            let lhsHealth = PopoverText.healthKinds.contains(lhs.kind)
            let rhsHealth = PopoverText.healthKinds.contains(rhs.kind)
            if lhsHealth != rhsHealth { return lhsHealth }
            return lhs.title < rhs.title
        }
        events = payload.events
        let today = calendar.startOfDay(for: payload.capturedAt)
        days = (-6...0).map { calendar.date(byAdding: .day, value: $0, to: today) ?? today }
        strip = payload.portDays.map { portDays in
            // Ports without counters (HDMI, some front ports) record nothing, so a row would say "No connections" wrongly.
            payload.snapshot.ports.filter { $0.statistics != nil || portDays[$0.key] != nil }.map { port in
                let week = portDays[port.key] ?? []
                let padded = Array(repeating: PortHealth(), count: max(0, 7 - week.count)) + week.suffix(7)
                return PortWeek(key: port.key, title: port.label.shortTitle, connector: port.label.connector,
                                days: padded.map(Self.day), summary: Self.summary(padded))
            }
        }
        if payload.portDays != nil {
            let ports = payload.portHealth.values
            let connections = ports.reduce(0) { $0 + $1.connections }
            let problems = ports.reduce(0) { $0 + $1.errors }
            week = "Last 7 days: "
                + (connections == 0 ? "no connections" : PopoverText.count(connections, "connection", "connections"))
                + " · " + (problems == 0 ? "no problems" : PopoverText.count(problems, "problem", "problems"))
        }
    }

    /// True when nothing is worse than a note.
    public var isHealthy: Bool { !findings.contains { $0.severity >= .warning } }

    /// "All links healthy", or "1 critical issue · 2 warnings · 1 note" in the Diagnostics page's words.
    public var headline: String {
        guard !isHealthy else { return "All links healthy" }
        var parts: [String] = []
        for severity in DiagnosticSeverity.allCases.reversed() {
            let count = findings.filter { $0.severity == severity }.count
            guard count > 0 else { continue }
            switch severity {
            case .critical: parts.append(PopoverText.count(count, "critical issue", "critical issues"))
            case .warning: parts.append(PopoverText.count(count, "warning", "warnings"))
            case .info: parts.append(PopoverText.count(count, "note", "notes"))
            }
        }
        return parts.joined(separator: " · ")
    }

    static func day(_ health: PortHealth) -> Day {
        if health.overcurrents > 0 || health.liquidDetections > 0 { return .critical }
        if health.errors > 0 { return .problems }
        if health.connections > 0 || health.plugEvents > 0 { return .used }
        return .quiet
    }

    static func summary(_ week: [PortHealth]) -> String {
        func total(_ value: KeyPath<PortHealth, Int>) -> Int { week.reduce(0) { $0 + $1[keyPath: value] } }
        if total(\.liquidDetections) > 0 { return "Liquid detected" }
        if total(\.overcurrents) > 0 { return "Overcurrent" }
        if total(\.errors) > 0 { return PopoverText.count(total(\.errors), "problem", "problems") }
        if total(\.connections) > 0 { return PopoverText.count(total(\.connections), "connection", "connections") }
        return "No connections"
    }

    /// The finding's detail split into its "Likely cause: the cable" sentence
    /// and the rest, so the cause can stand out.
    public static func likelyCause(_ detail: String) -> (cause: String?, rest: String) {
        // shortcut: reads the sentence `ConnectionHealth` writes; give `Diagnostic` a culprit field if it changes.
        guard let start = detail.range(of: "Likely cause: ") else { return (nil, detail) }
        let end = detail[start.upperBound...].firstIndex(of: ".") ?? detail.endIndex
        let after = end < detail.endIndex ? detail[detail.index(after: end)...] : ""
        let rest = [detail[..<start.lowerBound], after]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return (String(detail[start.lowerBound..<end]), rest)
    }
}
