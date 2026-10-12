// Portions adapted from WhatPort (MIT License, © 2025 Darryl Morley): the meaning
// of the battery-health bits in NotChargingReason.

import Foundation

/// Evaluates the diagnostic rules in SPEC §5.4 "Diagnostics".
///
/// Every rule fails closed: when a key is missing or has the wrong type, the
/// rule stays quiet rather than guessing.
public enum DiagnosticsEngine {
    /// - Parameters:
    ///   - snapshot: the freshly built snapshot (its `diagnostics` are ignored).
    ///   - raw: the raw capture it came from (for keys the model does not carry).
    ///   - baseline: overcurrent counts per port key at app launch, to detect increases.
    /// - Returns: findings sorted by severity (critical first), then by id.
    ///   Ids are `"<kind>:<subject id>"` and stay the same while the finding holds.
    public static func evaluate(_ snapshot: HostSnapshot, raw: RawSnapshot?, baseline: [String: Int] = [:]) -> [Diagnostic] {
        var findings: [Diagnostic] = []
        findings += usb2Fallbacks(snapshot)
        findings += thunderboltBottlenecks(snapshot, raw: raw)
        findings += chargerFindings(snapshot, raw: raw)
        findings += hubsOverBudget(snapshot)
        findings += deepChains(snapshot, raw: raw)
        findings += liquidDetections(snapshot)
        findings += overcurrents(snapshot, baseline: baseline)
        findings += reducedDetail(snapshot, raw: raw)

        var seen = Set<String>()
        let unique = findings.filter { seen.insert($0.id).inserted }
        return unique.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.id < rhs.id
        }
    }

    // MARK: Limits

    /// The most a bus-powered hub on a USB 3 link may hand to its devices.
    static let usb3HubBudgetMilliwatts = 4_500
    /// The most a bus-powered hub on a USB 2 link may hand to its devices.
    static let usb2HubBudgetMilliwatts = 2_500
    /// Thunderbolt depth beyond which a chain is reported.
    static let maxChainDepth = 5
    /// Chargers below this rating are reported when the Mac is not charging.
    static let minimumChargerWatts = 30
    /// The fastest rate a USB 2 link can reach.
    static let usb2MaxBitsPerSecond: Int64 = 480_000_000

    // MARK: USB 2 fallback

    /// USB 3 devices linked at 480 Mb/s or slower on a port that supports
    /// USB 3 or Thunderbolt. Devices below one that is already reported are
    /// skipped, since the upstream device explains them.
    static func usb2Fallbacks(_ snapshot: HostSnapshot) -> [Diagnostic] {
        var findings: [Diagnostic] = []
        for port in snapshot.ports
        where port.supportedTransports.contains(.usb3) || port.supportedTransports.contains(.cio) {
            for root in port.devices {
                collectUSB2Fallbacks(root, parent: nil, port: port, ancestorReported: false, into: &findings)
            }
        }
        return findings
    }

    private static func collectUSB2Fallbacks(_ device: DeviceNode, parent: DeviceNode?, port: PhysicalPort,
                                             ancestorReported: Bool, into findings: inout [Diagnostic]) {
        let isFallback = isUSB2Fallback(device)
        if isFallback && !ancestorReported {
            let name = displayName(device)
            let rate = device.link?.bitsPerSecond.map(Format.dataRate(bitsPerSecond:)) ?? "USB 2 speed"
            let version = device.usbVersion.map { "USB \($0)" } ?? "USB 3"
            var detail = "\(name) supports \(version) but is connected at \(rate) on \(port.label.title). "
                + "The port supports USB 3 at 5 Gb/s or faster."
            var suggestion = "Unplug it and plug it back in firmly. If it stays slow, try another cable: "
                + "many USB-C cables, including most charging cables, carry only USB 2 data."
            if let parent, isHub(parent), !isUSB3Capable(parent),
               let parentRate = parent.link?.bitsPerSecond, parentRate <= usb2MaxBitsPerSecond {
                detail += " It is connected through \(displayName(parent)), which only supports USB 2."
                suggestion = "Connect it directly to the Mac or through a USB 3 hub."
            }
            findings.append(Diagnostic(
                id: "\(DiagnosticKind.usb2Fallback.rawValue):\(device.id)",
                kind: .usb2Fallback,
                severity: .warning,
                title: "\(name) is running at USB 2 speed",
                detail: detail,
                suggestion: suggestion,
                portKey: port.key,
                deviceID: device.id))
        }
        for child in device.children {
            collectUSB2Fallbacks(child, parent: device, port: port, ancestorReported: ancestorReported || isFallback,
                                 into: &findings)
        }
    }

    /// A USB 3 device (`bcdUSB` 0x0300 or higher) whose link runs at 480 Mb/s or slower.
    static func isUSB2Fallback(_ device: DeviceNode) -> Bool {
        guard isUSB3Capable(device), let bps = device.link?.bitsPerSecond, bps > 0 else { return false }
        return bps <= usb2MaxBitsPerSecond
    }

    /// True when the device declares USB 3.0 or later, from `usbVersion` or
    /// the raw `bcdUSB` property.
    static func isUSB3Capable(_ device: DeviceNode) -> Bool {
        if let version = device.usbVersion,
           let major = version.split(separator: ".").first.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) {
            return major >= 3
        }
        if let bcd = device.properties?.int("bcdUSB") {
            return bcd >= 0x0300
        }
        return false
    }

    // MARK: Thunderbolt bottleneck

    /// Thunderbolt hops whose current speed is below what both ends support.
    ///
    /// A hop joins a switch's upstream lane port to the lane port of its
    /// parent switch that leads to it. Speed codes follow Linux `tb_regs.h`:
    /// 0x8 = 10 Gb/s, 0x4 = 20 Gb/s, 0x2 = 40 Gb/s per lane. The
    /// `Supported Link Speed` mask uses the same bits.
    static func thunderboltBottlenecks(_ snapshot: HostSnapshot, raw: RawSnapshot?) -> [Diagnostic] {
        guard let raw, !raw.thunderboltSwitches.isEmpty else { return [] }
        let switches = Dictionary(raw.thunderboltSwitches.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var findings: [Diagnostic] = []

        for child in raw.thunderboltSwitches {
            guard let parentID = child.parentSwitchID, let parent = switches[parentID],
                  let upstream = upstreamLanePort(of: child),
                  let downstream = downstreamLanePort(of: parent, toward: child) else { continue }

            let currentCode = nonZero(upstream.properties.int("Current Link Speed"))
                ?? nonZero(downstream.properties.int("Current Link Speed"))
            guard let currentCode, let currentRate = perLaneGbps(code: currentCode),
                  let childBest = supportedMask(port: upstream, of: child).flatMap(fastestPerLaneGbps(mask:)),
                  let parentBest = supportedMask(port: downstream, of: parent).flatMap(fastestPerLaneGbps(mask:))
            else { continue }

            let achievable = min(childBest, parentBest)
            guard achievable > currentRate else { continue }

            let device = thunderboltDevice(for: child, in: snapshot)
            let subject = device?.id ?? thunderboltSubjectID(for: child)
            let name = device.map(displayName) ?? thunderboltName(for: child)
            let portKey = device.flatMap { snapshot.port(containing: $0.id)?.key }
            let cable = achievable >= 40
                ? "a cable rated for 80 Gb/s (Thunderbolt 5)"
                : "a cable rated for 40 Gb/s (Thunderbolt 4 or USB4)"
            findings.append(Diagnostic(
                id: "\(DiagnosticKind.thunderboltBottleneck.rawValue):\(subject)",
                kind: .thunderboltBottleneck,
                severity: .info,
                title: "\(name) is linked slower than it could be",
                detail: "The Thunderbolt link to \(name) runs at \(currentRate) Gb/s per lane, "
                    + "but both ends support \(achievable) Gb/s per lane.",
                suggestion: "The cable is the usual limit. Use \(cable), and keep passive cables short.",
                portKey: portKey,
                deviceID: device?.id))
        }
        return findings
    }

    /// Per-lane rate in Gb/s for a Thunderbolt link-speed code.
    static func perLaneGbps(code: Int) -> Int? {
        switch code {
        case 0x8: return 10
        case 0x4: return 20
        case 0x2: return 40
        default: return nil
        }
    }

    /// The fastest per-lane rate a `Supported Link Speed` mask allows.
    static func fastestPerLaneGbps(mask: Int) -> Int? {
        [0x2, 0x4, 0x8].first { mask & $0 != 0 }.flatMap(perLaneGbps(code:))
    }

    private static func nonZero(_ value: Int?) -> Int? {
        guard let value, value != 0 else { return nil }
        return value
    }

    private static func isLanePort(_ node: RawNode) -> Bool {
        node.properties.string("Description") == "Thunderbolt Port"
    }

    private static func isActiveLane(_ node: RawNode) -> Bool {
        isLanePort(node) && nonZero(node.properties.int("Current Link Speed")) != nil
    }

    /// The child's lane port facing its parent: `Upstream Port Number`, or the
    /// only active lane port when that key is missing.
    static func upstreamLanePort(of sw: RawThunderboltSwitch) -> RawNode? {
        if let number = sw.node.properties.int("Upstream Port Number") {
            return sw.ports.first { $0.properties.int("Port Number") == number }
        }
        let active = sw.ports.filter(isActiveLane)
        return active.count == 1 ? active.first : nil
    }

    /// The parent's lane port that leads to `child`: the port among the
    /// child's registry ancestors, or else the parent's active lane ports
    /// (other than its own upstream port) when they all read the same speeds.
    static func downstreamLanePort(of parent: RawThunderboltSwitch, toward child: RawThunderboltSwitch) -> RawNode? {
        let ancestorIDs = Set(child.ancestry.map(\.id))
        if let port = parent.ports.first(where: { ancestorIDs.contains($0.id) }) {
            return port
        }
        let upstreamID = upstreamLanePort(of: parent)?.id
        let candidates = parent.ports.filter { isActiveLane($0) && $0.id != upstreamID }
        guard let first = candidates.first else { return nil }
        let signature = { (node: RawNode) in
            [node.properties.int("Current Link Speed"), node.properties.int("Supported Link Speed")]
        }
        return candidates.allSatisfy({ signature($0) == signature(first) }) ? first : nil
    }

    /// `Supported Link Speed` of a lane port, falling back to the switch's own
    /// key and then to every lane port of the switch.
    static func supportedMask(port: RawNode, of sw: RawThunderboltSwitch) -> Int? {
        if let mask = nonZero(port.properties.int("Supported Link Speed")) { return mask }
        if let mask = nonZero(sw.node.properties.int("Supported Link Speed")) { return mask }
        let combined = sw.ports.filter(isLanePort).reduce(0) { $0 | ($1.properties.int("Supported Link Speed") ?? 0) }
        return nonZero(combined)
    }

    /// The device node built from a switch, by registry ID or `tb:<UID>` id.
    static func thunderboltDevice(for sw: RawThunderboltSwitch, in snapshot: HostSnapshot) -> DeviceNode? {
        let devices = snapshot.allDevices.map(\.device)
        if let device = devices.first(where: { $0.registryID == sw.id }) { return device }
        guard let uid = thunderboltUIDHex(sw) else { return nil }
        return devices.first { device in
            guard device.id.lowercased().hasPrefix("tb:") else { return false }
            return normalizedHex(String(device.id.dropFirst(3))) == uid
        }
    }

    private static func thunderboltUIDHex(_ sw: RawThunderboltSwitch) -> String? {
        sw.node.properties.int64("UID").map { String(UInt64(bitPattern: $0), radix: 16) }
    }

    private static func normalizedHex(_ text: String) -> String {
        var hex = text.lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        while hex.count > 1 && hex.hasPrefix("0") { hex.removeFirst() }
        return hex
    }

    private static func thunderboltSubjectID(for sw: RawThunderboltSwitch) -> String {
        thunderboltUIDHex(sw).map { "tb:\($0)" } ?? "tbswitch:\(sw.id)"
    }

    /// "CalDigit TS4" from the switch's vendor and model names.
    static func thunderboltName(for sw: RawThunderboltSwitch) -> String {
        let vendor = sw.node.properties.string("Device Vendor Name")?.trimmingCharacters(in: .whitespaces)
        let model = sw.node.properties.string("Device Model Name")?.trimmingCharacters(in: .whitespaces)
        switch (vendor, model) {
        case let (vendor?, model?) where !vendor.isEmpty && !model.isEmpty:
            return model.lowercased().hasPrefix(vendor.lowercased()) ? model : "\(vendor) \(model)"
        case let (_, model?) where !model.isEmpty:
            return model
        case let (vendor?, _) where !vendor.isEmpty:
            return "\(vendor) device"
        default:
            return "Thunderbolt device"
        }
    }

    // MARK: Charger and battery

    /// `NotChargingReason` bits that mean macOS is holding the charge on
    /// purpose to protect the battery (Optimized Battery Charging or a charge
    /// limit). WhatPort verified bits 24 and 55 against the WhatCable corpus.
    static let batteryHealthHoldMask: Int64 = (1 << 24) | (1 << 55)

    /// The battery state from the snapshot, or from the raw battery keys.
    private struct ChargeState {
        var externalConnected: Bool
        var isCharging: Bool
        var isFullyCharged: Bool
        var notChargingReason: Int64
    }

    private static func chargeState(_ snapshot: HostSnapshot, raw: RawSnapshot?) -> ChargeState? {
        let rawReason: Int64? = raw?.battery.flatMap { bag in
            bag.bag("ChargerData")?.int64("NotChargingReason") ?? bag.int64("NotChargingReason")
        }
        if let battery = snapshot.power.battery {
            return ChargeState(externalConnected: battery.externalConnected, isCharging: battery.isCharging,
                               isFullyCharged: battery.isFullyCharged,
                               notChargingReason: battery.notChargingReason.map(Int64.init) ?? rawReason ?? 0)
        }
        guard let bag = raw?.battery, let connected = bag.bool("ExternalConnected") else { return nil }
        let charging = bag.bool("IsCharging") ?? bag.bag("ChargerData")?.bool("IsCharging") ?? false
        return ChargeState(externalConnected: connected, isCharging: charging,
                           isFullyCharged: bag.bool("FullyCharged") ?? false,
                           notChargingReason: rawReason ?? 0)
    }

    static func chargerFindings(_ snapshot: HostSnapshot, raw: RawSnapshot?) -> [Diagnostic] {
        guard let state = chargeState(snapshot, raw: raw), state.externalConnected,
              !state.isCharging, !state.isFullyCharged else { return [] }
        let healthHold = state.notChargingReason & batteryHealthHoldMask != 0
        var findings: [Diagnostic] = []

        if snapshot.machine.isLaptop, !healthHold, let charger = snapshot.power.charger,
           let watts = charger.ratedWatts, watts > 0, watts < minimumChargerWatts {
            let place = charger.portKey.flatMap { snapshot.port($0) }.map { " on \($0.label.title)" } ?? ""
            findings.append(Diagnostic(
                id: "\(DiagnosticKind.slowCharger.rawValue):charger",
                kind: .slowCharger,
                severity: .warning,
                title: "The \(watts) W charger is too weak to charge this Mac",
                detail: "\(charger.displayName)\(place) is rated at \(watts) W. The Mac is plugged in but not "
                    + "charging, which usually means it needs more power than this charger supplies.",
                suggestion: "Use a USB-C charger rated at \(minimumChargerWatts) W or more, "
                    + "ideally the wattage that came with this Mac.",
                portKey: charger.portKey))
        }

        if state.notChargingReason != 0 {
            let code = "0x" + String(UInt64(bitPattern: state.notChargingReason), radix: 16)
            let title: String
            let detail: String
            let suggestion: String?
            if healthHold {
                title = "Charging is on hold to protect the battery"
                detail = "macOS paused charging on purpose (reason \(code)), usually because Optimized Battery "
                    + "Charging or a charge limit is holding the battery around 80%."
                suggestion = "Nothing is wrong. Charging resumes on its own; to charge to 100% now, "
                    + "choose Charge to Full Now from the battery menu."
            } else {
                title = "The battery is not charging"
                detail = "The Mac is connected to power, but macOS reports that it is not charging (reason \(code)). "
                    + "This can happen when the battery is too warm or when the charger cannot supply enough power."
                suggestion = "Let the Mac cool down and check the charger and cable. If it persists, "
                    + "try another charger."
            }
            findings.append(Diagnostic(
                id: "\(DiagnosticKind.notCharging.rawValue):battery",
                kind: .notCharging,
                severity: .info,
                title: title,
                detail: detail,
                suggestion: suggestion,
                portKey: snapshot.power.charger?.portKey))
        }
        return findings
    }

    // MARK: Hub power budget

    /// Bus-powered hubs whose devices are allocated more power than the hub's
    /// upstream link can supply.
    static func hubsOverBudget(_ snapshot: HostSnapshot) -> [Diagnostic] {
        var findings: [Diagnostic] = []
        for (device, port, _) in snapshot.allDevices where isHub(device) && isBusPowered(device) {
            let allocated = device.children.reduce(0) { $0 + $1.rolledUpMilliwatts }
            let isUSB3 = isUSB3Link(device)
            let budget = isUSB3 ? usb3HubBudgetMilliwatts : usb2HubBudgetMilliwatts
            guard allocated > budget else { continue }
            let name = displayName(device)
            let count = device.descendantCount
            let devices = count == 1 ? "1 device" : "\(count) devices"
            let place = port.map { " on \($0.label.title)" } ?? ""
            findings.append(Diagnostic(
                id: "\(DiagnosticKind.hubOverBudget.rawValue):\(device.id)",
                kind: .hubOverBudget,
                severity: .warning,
                title: "\(name) may not have enough power",
                detail: "\(name)\(place) has no power supply of its own, and its \(devices) are allocated "
                    + "\(Format.power(milliwatts: allocated)). A \(isUSB3 ? "USB 3" : "USB 2") link supplies at most "
                    + "\(Format.power(milliwatts: budget)), so devices may disconnect or fail to start.",
                suggestion: "Use a hub with its own power adapter, or move drives and other power-hungry "
                    + "devices to another port.",
                portKey: port?.key,
                deviceID: device.id))
        }
        return findings
    }

    static func isHub(_ device: DeviceNode) -> Bool {
        device.kind == .hub || device.deviceClass == 9
    }

    /// True when the hub is known to draw its power from the Mac:
    /// `isSelfPowered == false`, or, when that is unknown, `kUSBHubPowerSupply`
    /// of 0 or `kUSBHubPowerSupplyType` of 2 in its raw properties.
    static func isBusPowered(_ device: DeviceNode) -> Bool {
        if let selfPowered = device.power?.isSelfPowered { return !selfPowered }
        guard let properties = device.properties else { return false }
        if let type = properties.int("kUSBHubPowerSupplyType") { return type == 2 }
        if let supply = properties.int("kUSBHubPowerSupply") { return supply == 0 }
        return false
    }

    /// True when the device's own link is USB 3 class (5 Gb/s or faster). When
    /// the rate is unknown, the declared USB version decides; an unknown hub
    /// gets the larger USB 3 budget so the rule does not over-report.
    static func isUSB3Link(_ device: DeviceNode) -> Bool {
        if let bps = device.link?.bitsPerSecond, bps > 0 { return bps > usb2MaxBitsPerSecond }
        if device.usbVersion != nil || device.properties?.int("bcdUSB") != nil { return isUSB3Capable(device) }
        return true
    }

    // MARK: Deep chains

    /// Thunderbolt chains deeper than `maxChainDepth`, one finding per tree,
    /// naming the deepest device. Falls back to raw switch depths when the
    /// snapshot carries no chain depths.
    static func deepChains(_ snapshot: HostSnapshot, raw: RawSnapshot?) -> [Diagnostic] {
        var findings: [Diagnostic] = []
        var sawDepth = false
        let roots: [(DeviceNode, PhysicalPort?)] = snapshot.ports.flatMap { port in port.devices.map { ($0, port) } }
            + snapshot.otherDevices.map { ($0, nil) }
        for (root, port) in roots {
            let chain = root.flattened().map(\.device).filter { $0.chainDepth != nil }
            if !chain.isEmpty { sawDepth = true }
            guard let deepest = chain.max(by: { ($0.chainDepth ?? 0) < ($1.chainDepth ?? 0) }),
                  let depth = deepest.chainDepth, depth > maxChainDepth else { continue }
            findings.append(deepChainFinding(subject: deepest.id, name: displayName(deepest), depth: depth,
                                             port: port, deviceID: deepest.id))
        }
        if !sawDepth, let raw {
            let deep = raw.thunderboltSwitches
                .compactMap { sw in sw.node.properties.int("Depth").map { (sw, $0) } }
                .filter { $0.1 > maxChainDepth }
                // Deepest first; on a tie, the lowest registry ID, so the choice is stable.
                .max { lhs, rhs in lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.id > rhs.0.id }
            if let (sw, depth) = deep {
                let device = thunderboltDevice(for: sw, in: snapshot)
                findings.append(deepChainFinding(
                    subject: device?.id ?? thunderboltSubjectID(for: sw),
                    name: device.map(displayName) ?? thunderboltName(for: sw),
                    depth: depth,
                    port: device.flatMap { snapshot.port(containing: $0.id) },
                    deviceID: device?.id))
            }
        }
        return findings
    }

    private static func deepChainFinding(subject: String, name: String, depth: Int, port: PhysicalPort?,
                                         deviceID: String?) -> Diagnostic {
        let place = port.map { " on \($0.label.title)" } ?? ""
        return Diagnostic(
            id: "\(DiagnosticKind.deepChain.rawValue):\(subject)",
            kind: .deepChain,
            severity: .info,
            title: "Thunderbolt chain is \(depth) devices deep",
            detail: "\(name)\(place) is \(depth) devices away from the Mac. Thunderbolt supports chains of up to "
                + "six devices, and every device in a long chain shares the same link to the Mac.",
            suggestion: "Move some devices to another Thunderbolt port, or use a dock with several "
                + "downstream ports to shorten the chain.",
            portKey: port?.key,
            deviceID: deviceID)
    }

    // MARK: Liquid and overcurrent

    static func liquidDetections(_ snapshot: HostSnapshot) -> [Diagnostic] {
        snapshot.ports.compactMap { port in
            let detected = port.liquidDetected || port.properties?.bool("LDCM_LiquidDetected") == true
            guard detected else { return nil }
            return Diagnostic(
                id: "\(DiagnosticKind.liquidDetected.rawValue):\(port.id)",
                kind: .liquidDetected,
                severity: .critical,
                title: "Liquid detected in \(port.label.title)",
                detail: "macOS detected moisture or debris in \(port.label.title). "
                    + "Power and data on this port may be limited until it is dry and clean.",
                suggestion: "Unplug the cable, let the port dry completely and make sure it is free of debris. "
                    + "Do not charge through this port until the warning clears.",
                portKey: port.key)
        }
    }

    static func overcurrents(_ snapshot: HostSnapshot, baseline: [String: Int]) -> [Diagnostic] {
        snapshot.ports.compactMap { port in
            guard let start = baseline[port.id],
                  let count = port.statistics?.overcurrentCount ?? port.properties?.int("Overcurrent Count"),
                  count > start else { return nil }
            let increase = count - start
            let times = increase == 1 ? "once" : "\(increase) times"
            return Diagnostic(
                id: "\(DiagnosticKind.overcurrent.rawValue):\(port.id)",
                kind: .overcurrent,
                severity: .warning,
                title: "\(port.label.title) cut power to protect the Mac",
                detail: "A device or cable on \(port.label.title) tried to draw more current than the port allows. "
                    + "This has happened \(times) since Bus Stop started.",
                suggestion: "Unplug what is on this port and check the cable and device for damage. "
                    + "Use a powered hub for devices that need a lot of power.",
                portKey: port.key)
        }
    }

    // MARK: Reduced detail

    static func reducedDetail(_ snapshot: HostSnapshot, raw: RawSnapshot?) -> [Diagnostic] {
        let detail: String
        if !snapshot.machine.isAppleSilicon {
            detail = "This Mac does not have Apple silicon port controllers, so Bus Stop can list USB and "
                + "Thunderbolt devices but not port names, transports or per-port power."
        } else if snapshot.ports.isEmpty {
            detail = "macOS did not report any physical ports, so devices are listed without the port "
                + "they are plugged into."
        } else if let note = (snapshot.captureNotes + (raw?.captureNotes ?? [])).first(where: saysPortDetailsUnavailable) {
            detail = "Some port details could not be read (\(note)), so parts of the map may be missing."
        } else {
            return []
        }
        return [Diagnostic(
            id: "\(DiagnosticKind.reducedDetail.rawValue):machine",
            kind: .reducedDetail,
            severity: .info,
            title: "Port details are limited on this Mac",
            detail: detail,
            portKey: nil)]
    }

    /// True for capture notes such as "Port details unavailable" or "port
    /// controller data not available".
    static func saysPortDetailsUnavailable(_ note: String) -> Bool {
        let text = note.lowercased()
        return text.contains("port") && (text.contains("unavailable") || text.contains("not available"))
    }

    // MARK: Helpers

    static func displayName(_ device: DeviceNode) -> String {
        let name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? device.kind.displayName : name
    }
}
