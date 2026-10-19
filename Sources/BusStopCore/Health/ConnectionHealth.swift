import Foundation

/// What most likely causes a connection that keeps dropping.
public enum LikelyCulprit: String, Sendable, Hashable {
    case cable
    case device
    case port
    case hub

    /// "the cable", for "Likely cause: the cable."
    public var phrase: String {
        switch self {
        case .cable: return "the cable"
        case .device: return "the device"
        case .port: return "the port"
        case .hub: return "the hub"
        }
    }
}

/// One device's recent connection record, for the inspector.
public struct DeviceConnectionHistory: Sendable, Hashable {
    /// Disconnects followed by a reconnect to the same Mac port within `ConnectionHealth.window`.
    public var cycles: Int
    /// The fastest link the device has had on this Mac port since Bus Stop started.
    public var bestLink: LinkInfo?
    public var lastLink: LinkInfo?
    /// Set once the device has dropped often enough to raise a finding.
    public var culprit: LikelyCulprit?
}

/// Watches consecutive snapshots for connections that keep dropping, links
/// that keep changing speed and devices running slower than they have before
/// on the same port (SPEC §5.4, "Connection health").
///
/// Devices are followed by `DeviceIdentity`, so a drive that comes back on
/// another controller is still the same drive. Every rule fails closed: a
/// device without an identity, a disconnect soon after a gap (launch, wake)
/// and a device that was present only briefly (a dock enumerating in stages)
/// count for nothing. A finding stays raised until its window has been quiet,
/// so it does not toggle on every capture.
///
/// Feed every new capture once, in order. Finding ids carry `DeviceNode` ids
/// or port keys, never a serial number.
public struct ConnectionHealth: Sendable {
    /// How far back cycles and speed reversals count.
    public static let window: TimeInterval = 600
    /// Cycles or reversals within `window` that raise a finding.
    public static let threshold = 3
    /// Disconnects this soon after a gap (launch, wake) are re-enumeration, not flakiness.
    public static let settleTime: TimeInterval = 15
    /// A device must have been present this long before it leaves for the leave to count.
    /// Time, not a capture count: while the screens sleep, captures come only on hardware changes.
    public static let minimumPresence: TimeInterval = 2

    /// One device as last seen.
    struct Seen: Sendable {
        var deviceID: String
        /// The dock for one of its built-in parts, else the device.
        var subjectID: String
        var name: String
        var port: PortKey?
        var parentDeviceID: String?
        var parentIdentity: String?
        var link: LinkInfo?
        /// When it arrived; for a device in `away`, when it left.
        var since: Date
    }

    struct Cycle: Sendable {
        var date: Date
        var port: PortKey?
        /// The identity of what the device hung off when it came back; nil at a port.
        var parent: String?
    }

    private var present: [String: Seen] = [:]
    /// Devices whose leave counted, until they come back.
    private var away: [String: Seen] = [:]
    /// The last sighting of every device with a cycle or reversal on record, to name it while it is gone.
    private var known: [String: Seen] = [:]
    private var cycles: [String: [Cycle]] = [:]
    private var reversals: [String: [Date]] = [:]
    private var lastDirection: [String: SnapshotDiffer.LinkChange] = [:]
    /// Fastest link per `"<identity>@<PortKey>"`.
    private var best: [String: LinkInfo] = [:]
    private var plugEvents: [PortKey: Int] = [:]
    private var sharedSerials = Set<String>()
    private var settleUntil = Date.distantPast
    /// Finding id per subject (`"flaky:<identity>"`, `"port:<key>"`, …), fixed at first raise.
    private var raisedIDs: [String: String] = [:]
    private var flaky: Set<String> = []
    private var flapping: Set<String> = []

    public init() {}

    /// Takes in the next capture and returns the findings that hold now.
    /// Pass `afterGap` for the first capture after launch, wake or a change
    /// of source: nothing is compared across it.
    public mutating func observe(_ snapshot: HostSnapshot, afterGap: Bool) -> [Diagnostic] {
        let now = snapshot.capturedAt
        if afterGap {
            settleUntil = now.addingTimeInterval(Self.settleTime)
            away.removeAll()
        }
        let settled = !afterGap && now >= settleUntil
        let current = seen(in: snapshot, now: now)
        let presentIDs = Set(snapshot.allDevices.map(\.device.id)).union(snapshot.internalPartIDs)

        // Leaves: only the top-most device of what left together, after it had settled in.
        if settled {
            for (identity, old) in present where current[identity] == nil {
                let parentStayed = old.parentDeviceID.map(presentIDs.contains) ?? true
                if parentStayed && now.timeIntervalSince(old.since) >= Self.minimumPresence {
                    var gone = old
                    gone.since = now
                    away[identity] = gone
                }
            }
        }
        // Returns to the same Mac port are cycles; a move to another port is not.
        for (identity, new) in current where present[identity] == nil {
            if let old = away.removeValue(forKey: identity), old.port == new.port {
                cycles[identity, default: []].append(Cycle(date: now, port: new.port, parent: new.parentIdentity))
            }
        }
        if !afterGap {
            countLinkReversals(current, now: now)
            countHiddenCycles(snapshot, current: current, now: now, settled: settled)
        }
        for port in snapshot.ports {
            if let count = port.statistics?.plugEventCount { plugEvents[port.key] = count }
        }
        present = current
        lastDirection = lastDirection.filter { current[$0.key] != nil }
        known.merge(current) { $1 }
        prune(now: now)
        return findings(snapshot, now: now, settled: settled)
    }

    /// The connection record of a device in the last capture observed.
    public func history(ofDevice id: String) -> DeviceConnectionHistory? {
        guard let (identity, seen) = present.first(where: { $0.value.deviceID == id }) else { return nil }
        let count = cycles[identity]?.count ?? 0
        return DeviceConnectionHistory(
            cycles: count,
            bestLink: seen.port.flatMap { best["\(identity)@\($0)"] },
            lastLink: seen.link,
            culprit: flaky.contains(identity) ? culprit(of: identity).culprit : nil)
    }

    // MARK: Observing

    private mutating func seen(in snapshot: HostSnapshot, now: Date) -> [String: Seen] {
        let keys = DeviceIdentity.keys(in: snapshot, sharedSerials: &sharedSerials)
        var result: [String: Seen] = [:]
        for entry in DeviceIdentity.Entry.all(in: snapshot) {
            guard let identity = keys[entry.node.id] else { continue }
            let subject = entry.dock ?? entry.node
            result[identity] = Seen(
                deviceID: entry.node.id, subjectID: subject.id, name: DiagnosticsEngine.displayName(subject),
                port: entry.port?.key, parentDeviceID: entry.parentID,
                parentIdentity: entry.parentID.flatMap { keys[$0] }, link: entry.node.link,
                since: present[identity]?.since ?? now)
        }
        return result
    }

    /// Direction reversals of USB and Thunderbolt links between two captures.
    /// DisplayPort retrains on a mode change or wake, so it is left out, and
    /// `SnapshotDiffer.linkChange` already ignores Thunderbolt 5 Bandwidth Boost.
    private mutating func countLinkReversals(_ current: [String: Seen], now: Date) {
        for (identity, new) in current {
            guard let old = present[identity], let from = old.link, let to = new.link,
                  Self.isDataLink(from), Self.isDataLink(to),
                  let change = SnapshotDiffer.linkChange(from: from, to: to) else { continue }
            if let last = lastDirection[identity], last != change { reversals[identity, default: []].append(now) }
            lastDirection[identity] = change
        }
    }

    /// `Plug Event Count` moves on plugs and unplugs faster than a capture,
    /// so on a Mac port whose devices did not change, half its increase is
    /// cycles of the device plugged into the port.
    private mutating func countHiddenCycles(_ snapshot: HostSnapshot, current: [String: Seen], now: Date,
                                            settled: Bool) {
        for port in snapshot.ports {
            guard settled, let count = port.statistics?.plugEventCount, let before = plugEvents[port.key],
                  count > before else { continue }
            let was = Set(present.filter { $0.value.port == port.key }.keys)
            let isNow = Set(current.filter { $0.value.port == port.key }.keys)
            guard was == isNow, let root = port.devices.first,
                  let identity = current.first(where: { $0.value.deviceID == root.id })?.key else { continue }
            for _ in 0..<((count - before) / 2) {
                cycles[identity, default: []].append(Cycle(date: now, port: port.key, parent: nil))
            }
        }
    }

    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.window)
        cycles = cycles.compactMapValues { list in
            let kept = list.filter { $0.date > cutoff }
            return kept.isEmpty ? nil : kept
        }
        reversals = reversals.compactMapValues { list in
            let kept = list.filter { $0 > cutoff }
            return kept.isEmpty ? nil : kept
        }
        away = away.filter { $0.value.since > cutoff }
        known = known.filter { present[$0.key] != nil || cycles[$0.key] != nil || reversals[$0.key] != nil }
    }

    private static func isDataLink(_ link: LinkInfo) -> Bool {
        link.family == .usb || link.family == .thunderbolt
    }

    // MARK: Findings

    private mutating func findings(_ snapshot: HostSnapshot, now: Date, settled: Bool) -> [Diagnostic] {
        var result: [Diagnostic] = []
        var raisedNow: [String: String] = [:]
        func id(_ kind: DiagnosticKind, _ subject: String, _ deviceID: String) -> String {
            let id = raisedIDs["\(kind.rawValue):\(subject)"] ?? "\(kind.rawValue):\(deviceID)"
            raisedNow["\(kind.rawValue):\(subject)"] = id
            return id
        }

        // Flaky connections, one finding per culprit.
        flaky = Set(cycles.filter { identity, list in
            list.count >= Self.threshold || (flaky.contains(identity) && !list.isEmpty)
        }.keys)
        var covered = Set<String>()
        for identity in flaky.sorted() where !covered.contains(identity) {
            let (culprit, group) = culprit(of: identity)
            covered.formUnion(group)
            guard let seen = present[identity] ?? known[identity] else { continue }
            let port = seen.port.flatMap { snapshot.port($0) }
            switch culprit {
            case .port:
                // Where it dropped; the device may have moved to another port since.
                guard let port = cycles[identity]?.last?.port.flatMap({ snapshot.port($0) }) else { continue }
                result.append(portFinding(port, devices: group.count,
                                          id: id(.flakyConnection, "port:\(port.key)", "port:\(port.key)")))
            case .hub:
                guard let hubIdentity = cycles[identity]?.last?.parent, let hub = present[hubIdentity] else { continue }
                result.append(hubFinding(hub, devices: group.count, port: port, snapshot: snapshot,
                                         id: id(.flakyConnection, "hub:\(hubIdentity)", hub.subjectID)))
            case .cable, .device:
                let count = cycles[identity]?.count ?? 0
                result.append(deviceFinding(seen, cycles: count, culprit: culprit, port: port,
                                            id: id(.flakyConnection, "flaky:\(identity)", seen.subjectID)))
            }
        }

        // Links that keep changing speed.
        flapping = Set(reversals.filter { identity, list in
            list.count >= Self.threshold || (flapping.contains(identity) && !list.isEmpty)
        }.keys)
        for identity in flapping.sorted() {
            guard let seen = present[identity] else { continue }
            let port = seen.port.flatMap { snapshot.port($0) }
            let count = reversals[identity]?.count ?? 0
            let name = seen.name
            var detail = "The link to \(name)\(place(port)) changed speed back and forth \(count) times in the last "
                + "10 minutes"
            if let link = seen.link { detail += ", and now runs at \(link.label)" }
            result.append(Diagnostic(
                id: id(.linkFlapping, "flap:\(identity)", seen.subjectID),
                kind: .linkFlapping,
                severity: .warning,
                title: "\(name) keeps changing speed",
                detail: detail + ". Likely cause: the cable.",
                suggestion: "A link that keeps retraining usually has a marginal cable or connector. Push both ends "
                    + "in fully, and try a shorter cable or one rated for a higher speed.",
                portKey: seen.port,
                deviceID: seen.subjectID))
        }

        // Slower than its own best on this port.
        for (identity, seen) in present.sorted(by: { $0.key < $1.key }) {
            guard let key = seen.port, let port = snapshot.port(key), let link = seen.link, Self.isDataLink(link),
                  port.supportedTransports.contains(.usb3) || port.supportedTransports.contains(.cio) else { continue }
            let bestKey = "\(identity)@\(key)"
            guard let previous = best[bestKey], let change = SnapshotDiffer.linkChange(from: previous, to: link) else {
                if best[bestKey] == nil { best[bestKey] = link }
                continue
            }
            if change == .faster {
                best[bestKey] = link
                continue
            }
            guard settled || raisedIDs["\(DiagnosticKind.speedRegression.rawValue):\(identity)"] != nil,
                  let node = snapshot.device(id: seen.deviceID) ?? snapshot.dock(withPart: seen.deviceID),
                  !DiagnosticsEngine.isUSB2Fallback(node) else { continue }
            let name = seen.name
            let bestRate = previous.rateLabel ?? previous.label
            let rate = link.rateLabel ?? link.label
            result.append(Diagnostic(
                id: id(.speedRegression, identity, seen.subjectID),
                kind: .speedRegression,
                severity: .warning,
                title: "\(name) is running slower than before",
                detail: "\(name) is connected at \(rate) on \(port.label.title), but it ran at \(bestRate) on this "
                    + "port earlier. Likely cause: the cable.",
                suggestion: "Unplug it and plug it back in firmly. If it stays slow, try another cable: a worn cable, "
                    + "or one that carries only USB 2 data, often causes this.",
                portKey: key,
                deviceID: seen.subjectID))
        }
        raisedIDs = raisedNow
        return result
    }

    /// The likely culprit for a flaky device, and every device the finding covers.
    private func culprit(of identity: String) -> (culprit: LikelyCulprit, group: Set<String>) {
        let own = cycles[identity] ?? []
        let ports = Set(own.map(\.port))
        if ports.count >= 2 { return (.device, [identity]) }
        guard let last = own.last else { return (.cable, [identity]) }
        // Several devices behind one hub that stayed connected.
        if let hub = last.parent, present[hub] != nil {
            let siblings = Set(cycles.filter { $0.value.last?.parent == hub }.keys)
            if siblings.count >= 2 { return (.hub, siblings) }
        }
        // Several devices straight on one port, none of them flaky on another port.
        if last.parent == nil, let port = last.port {
            let onPort = Set(cycles.filter { _, list in
                list.allSatisfy { $0.port == port && $0.parent == nil }
            }.keys)
            if onPort.count >= Self.threshold { return (.port, onPort) }
        }
        return (.cable, [identity])
    }

    private func place(_ port: PhysicalPort?) -> String {
        port.map { " on \($0.label.title)" } ?? ""
    }

    private func deviceFinding(_ seen: Seen, cycles count: Int, culprit: LikelyCulprit, port: PhysicalPort?,
                               id: String) -> Diagnostic {
        let suggestion = culprit == .device
            ? "It drops on more than one port, so the device itself is the likely cause. Check its power supply "
                + "and firmware, or try it with another Mac."
            : "Try another cable and push both ends in fully. If it keeps dropping with a good cable, the device "
                + "may be at fault."
        return Diagnostic(
            id: id,
            kind: .flakyConnection,
            severity: .warning,
            title: "\(seen.name) keeps disconnecting",
            detail: "\(seen.name)\(place(port)) disconnected and came back \(count) times in the last 10 minutes. "
                + "Likely cause: \(culprit.phrase).",
            suggestion: suggestion,
            portKey: seen.port,
            deviceID: seen.subjectID)
    }

    private func portFinding(_ port: PhysicalPort, devices: Int, id: String) -> Diagnostic {
        var detail = "\(devices) devices disconnected and came back on \(port.label.title) in the last 10 minutes, "
            + "and none of them did on another port. Likely cause: the port."
        if port.liquidDetected { detail += " macOS has also detected liquid in this port." }
        if let overcurrent = port.statistics?.overcurrentCount, overcurrent > 0 {
            detail += " It has cut power to protect the Mac \(overcurrent == 1 ? "once" : "\(overcurrent) times")."
        }
        return Diagnostic(
            id: id,
            kind: .flakyConnection,
            severity: .warning,
            title: "Devices keep disconnecting from \(port.label.title)",
            detail: detail,
            suggestion: "Use another port for now, and check this one for dust, lint or damage.",
            portKey: port.key)
    }

    private func hubFinding(_ hub: Seen, devices: Int, port: PhysicalPort?, snapshot: HostSnapshot,
                            id: String) -> Diagnostic {
        var detail = "\(devices) devices behind \(hub.name)\(place(port)) disconnected and came back in the last "
            + "10 minutes while the hub stayed connected. Likely cause: the hub."
        var suggestion = "Try another cable for the hub, or another hub."
        if let node = snapshot.device(id: hub.deviceID), DiagnosticsEngine.isBusPowered(node) {
            detail += " It has no power supply of its own, so it may not have enough power for them."
            suggestion = "Use a hub with its own power adapter, or move power-hungry devices to another port."
        }
        return Diagnostic(
            id: id,
            kind: .flakyConnection,
            severity: .warning,
            title: "Devices behind \(hub.name) keep disconnecting",
            detail: detail,
            suggestion: suggestion,
            portKey: hub.port,
            deviceID: hub.subjectID)
    }
}
