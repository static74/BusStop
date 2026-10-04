import Foundation

/// Turns raw IOKit speed codes and rates into `LinkInfo` values.
///
/// Every decoder returns nil for values it does not recognise instead of
/// guessing. Thunderbolt speed codes follow the Linux `tb_regs.h` encoding:
/// a code gives a per-lane rate only, never a protocol generation (see
/// `docs/SPEC.md` §5.4).
enum LinkDecoding {
    // MARK: - USB rates

    static let lowSpeed: Int64 = 1_500_000
    static let fullSpeed: Int64 = 12_000_000
    static let highSpeed: Int64 = 480_000_000
    static let superSpeed: Int64 = 5_000_000_000
    static let superSpeedPlus: Int64 = 10_000_000_000
    static let superSpeedPlus2x2: Int64 = 20_000_000_000

    /// USB generation name for a signalling rate, rounding up to the nearest
    /// standard rate.
    static func usbGeneration(bitsPerSecond bps: Int64) -> String {
        switch bps {
        case ...lowSpeed: return "USB 1.1 Low Speed"
        case ...fullSpeed: return "USB 1.1 Full Speed"
        case ...highSpeed: return "USB 2.0"
        case ...superSpeed: return "USB 3.2 Gen 1"
        case ...superSpeedPlus: return "USB 3.2 Gen 2"
        case ...superSpeedPlus2x2: return "USB 3.2 Gen 2x2"
        default: return "USB4"
        }
    }

    static func usbLink(bitsPerSecond bps: Int64, detail: String? = nil) -> LinkInfo {
        LinkInfo(family: .usb, generation: usbGeneration(bitsPerSecond: bps), bitsPerSecond: bps, detail: detail)
    }

    /// Rate for the legacy `Device Speed` enum:
    /// 0 Low, 1 Full, 2 High, 3 SuperSpeed, 4 SuperSpeed+ 10G, 5 SuperSpeed+ 20G.
    static func legacyDeviceSpeed(_ code: Int) -> Int64? {
        switch code {
        case 0: return lowSpeed
        case 1: return fullSpeed
        case 2: return highSpeed
        case 3: return superSpeed
        case 4: return superSpeedPlus
        case 5: return superSpeedPlus2x2
        default: return nil
        }
    }

    /// Rate for `USBSpeed` (`tIOUSBHostConnectionSpeed`):
    /// 1 Full, 2 Low, 3 High, 4 Super, 5 Super+, 6 Super+ 2x2. 0 means none.
    static func hostConnectionSpeed(_ code: Int) -> Int64? {
        switch code {
        case 1: return fullSpeed
        case 2: return lowSpeed
        case 3: return highSpeed
        case 4: return superSpeed
        case 5: return superSpeedPlus
        case 6: return superSpeedPlus2x2
        default: return nil
        }
    }

    /// The negotiated link of an `IOUSBHostDevice`.
    ///
    /// `UsbLinkSpeed` (bits/s) wins; then `Device Speed`; then `USBSpeed`.
    /// The two enums use different numbering, so each value is decoded only
    /// with its own table.
    static func usbDeviceLink(_ properties: PropertyBag) -> LinkInfo? {
        if let bps = properties.int64("UsbLinkSpeed"), bps > 0 {
            return usbLink(bitsPerSecond: bps)
        }
        if let code = properties.int("Device Speed"), let bps = legacyDeviceSpeed(code) {
            return usbLink(bitsPerSecond: bps)
        }
        if let code = properties.int("USBSpeed"), let bps = hostConnectionSpeed(code) {
            return usbLink(bitsPerSecond: bps)
        }
        return nil
    }

    // MARK: - Port transports

    /// Link of an `IOPortTransportStateUSB2` node. `DataRate` 1/2/3 means
    /// low, full and high speed; without it the `DataRateDescription` text is
    /// parsed, and a USB 2 transport with neither runs at 480 Mb/s.
    static func usb2TransportLink(_ properties: PropertyBag?) -> LinkInfo {
        let description = properties?.string("DataRateDescription")
        var bps: Int64?
        switch properties?.int("DataRate") {
        case 1?: bps = lowSpeed
        case 2?: bps = fullSpeed
        case 3?: bps = highSpeed
        default: bps = nil
        }
        if bps == nil, let description, let parsed = parseRate(description), parsed <= highSpeed {
            bps = parsed
        }
        return usbLink(bitsPerSecond: bps ?? highSpeed, detail: description)
    }

    /// Link of an `IOPortTransportStateUSB3` node.
    ///
    /// `SuperSpeedSignaling` 1 is Gen 1 (5 Gb/s) and 2 is Gen 2 (10 Gb/s).
    /// Two lanes, or a description containing "x2", doubles the rate.
    /// Without any signalling information the generation is "USB 3" with no
    /// rate.
    static func usb3TransportLink(_ properties: PropertyBag?) -> LinkInfo {
        let description = properties?.string(["SuperSpeedSignalingDescription", "GenerationDescription"])
        let lowered = description?.lowercased() ?? ""
        let lanes = properties?.int(["LaneCount", "Lane Count", "Lanes"])
        let isDual = (lanes ?? 1) >= 2 || lowered.contains("x2")

        var gen: Int?
        switch properties?.int("SuperSpeedSignaling") {
        case 1?: gen = 1
        case 2?: gen = 2
        default:
            if lowered.contains("gen 2") || lowered.contains("gen2") {
                gen = 2
            } else if lowered.contains("gen 1") || lowered.contains("gen1") {
                gen = 1
            }
        }

        switch (gen, isDual) {
        case (2?, true):
            return LinkInfo(family: .usb, generation: "USB 3.2 Gen 2x2", bitsPerSecond: superSpeedPlus2x2, lanes: 2)
        case (2?, false):
            return LinkInfo(family: .usb, generation: "USB 3.2 Gen 2", bitsPerSecond: superSpeedPlus)
        case (1?, true):
            return LinkInfo(family: .usb, generation: "USB 3.2 Gen 1x2", bitsPerSecond: superSpeedPlus, lanes: 2)
        case (1?, false):
            return LinkInfo(family: .usb, generation: "USB 3.2 Gen 1", bitsPerSecond: superSpeed)
        default:
            return LinkInfo(family: .usb, generation: "USB 3")
        }
    }

    /// DisplayPort per-lane rates, keyed by the short names macOS uses in
    /// `LinkRateDescription`. Ordered so that longer names are tried first
    /// ("UHBR13.5" before "HBR", "HBR3" before "HBR").
    static let displayPortRates: [(name: String, bitsPerSecond: Int64)] = [
        ("UHBR13.5", 13_500_000_000),
        ("UHBR20", 20_000_000_000),
        ("UHBR10", 10_000_000_000),
        ("HBR3", 8_100_000_000),
        ("HBR2", 5_400_000_000),
        ("HBR", 2_700_000_000),
        ("RBR", 1_620_000_000),
    ]

    /// Short rate name for a numeric `LinkRate`, as macOS numbers them:
    /// 1 RBR, 2 HBR, 3 HBR2, 4 HBR3, 5 UHBR10, 6 UHBR13.5, 7 UHBR20.
    /// 0 means no link.
    static func displayPortRateName(code: Int) -> String? {
        switch code {
        case 1: return "RBR"
        case 2: return "HBR"
        case 3: return "HBR2"
        case 4: return "HBR3"
        case 5: return "UHBR10"
        case 6: return "UHBR13.5"
        case 7: return "UHBR20"
        default: return nil
        }
    }

    /// Link of an `IOPortTransportStateDisplayPort` node: per-lane rate from
    /// `LinkRateDescription` or `LinkRate`, times `LaneCount`. The detail reads
    /// like "HBR3 × 4".
    static func displayPortLink(_ properties: PropertyBag?) -> LinkInfo {
        var rateName: String?
        var perLane: Int64?

        if let description = properties?.string("LinkRateDescription") {
            let upper = description.uppercased()
            if let match = displayPortRates.first(where: { upper.contains($0.name) }) {
                rateName = match.name
                perLane = match.bitsPerSecond
            } else if let parsed = parseRate(description), parsed > 0 {
                perLane = parsed
                rateName = displayPortRates.first(where: { $0.bitsPerSecond == parsed })?.name
            }
        }
        if perLane == nil, let code = properties?.int("LinkRate"), let name = displayPortRateName(code: code) {
            rateName = name
            perLane = displayPortRates.first(where: { $0.name == name })?.bitsPerSecond
        }

        var lanes = properties?.int("LaneCount")
        if let count = lanes, !(1...4).contains(count) { lanes = nil }

        var total: Int64?
        if let perLane, let lanes { total = perLane * Int64(lanes) }

        var detail: String?
        let perLaneText = rateName ?? perLane.map(Format.dataRate(bitsPerSecond:))
        if let perLaneText {
            detail = lanes.map { "\(perLaneText) × \($0)" } ?? perLaneText
        }
        return LinkInfo(family: .displayPort, generation: "DisplayPort", bitsPerSecond: total, lanes: lanes, detail: detail)
    }

    // MARK: - Thunderbolt / USB4

    /// Per-lane rate in Gb/s for a `Current Link Speed` code:
    /// 0x8 = 10, 0x4 = 20, 0x2 = 40. Anything else (including 0, idle) is nil.
    static func thunderboltPerLaneGbps(speedCode: Int) -> Int? {
        switch speedCode {
        case 0x8: return 10
        case 0x4: return 20
        case 0x2: return 40
        default: return nil
        }
    }

    /// Lanes for a `Current Link Width` bitmask: 0x1 one lane, 0x2 two lanes,
    /// 0x4 / 0x8 asymmetric (three lanes one way, one the other). Zero means
    /// no link.
    static func thunderboltWidth(code: Int) -> (lanes: Int, isAsymmetric: Bool)? {
        if code & 0xC != 0 { return (3, true) }
        if code & 0x2 != 0 { return (2, false) }
        if code & 0x1 != 0 { return (1, false) }
        return nil
    }

    /// Generation label for a total Thunderbolt / USB4 rate. Deliberately
    /// coarse: the speed code alone cannot tell Thunderbolt 3 from USB4.
    static func thunderboltGeneration(totalGbps: Int) -> String {
        if totalGbps >= 80 { return "USB4 v2 / TB5" }
        if totalGbps >= 20 { return "Thunderbolt / USB4" }
        return "Thunderbolt"
    }

    /// The trained link of an `IOThunderboltPort` lane adapter, or nil when
    /// the speed or width code says there is no link. Liveness beyond that
    /// (idle lanes on older controllers still report 0x8 / 0x1) is decided by
    /// `ThunderboltParser`.
    static func thunderboltLink(lanePort properties: PropertyBag) -> LinkInfo? {
        guard let speed = properties.int("Current Link Speed"),
              let perLane = thunderboltPerLaneGbps(speedCode: speed),
              let widthCode = properties.int("Current Link Width"),
              let width = thunderboltWidth(code: widthCode) else { return nil }
        let total = perLane * width.lanes
        let detail = width.isAsymmetric
            ? "3 × \(perLane) Gb/s one way, 1 × \(perLane) Gb/s the other"
            : "\(width.lanes) × \(perLane) Gb/s"
        return LinkInfo(family: .thunderbolt, generation: thunderboltGeneration(totalGbps: total),
                        bitsPerSecond: Int64(total) * 1_000_000_000, lanes: width.lanes,
                        isAsymmetric: width.isAsymmetric, detail: detail)
    }

    // MARK: - Helpers

    /// Parses the first rate in text such as "480 Mbps (High Speed)",
    /// "8.1 Gbps (HBR3)" or "10 Gb/s". Returns bits per second.
    static func parseRate(_ text: String) -> Int64? {
        let lowered = text.lowercased()
        let characters = Array(lowered)
        var i = 0
        while i < characters.count {
            guard characters[i].isASCII, characters[i].isNumber else { i += 1; continue }
            var j = i
            var number = ""
            while j < characters.count, characters[j].isASCII, characters[j].isNumber || characters[j] == "." {
                number.append(characters[j])
                j += 1
            }
            var k = j
            while k < characters.count, characters[k] == " " { k += 1 }
            let rest = String(characters[k..<characters.count])
            let multiplier: Double?
            if rest.hasPrefix("gbps") || rest.hasPrefix("gb/s") || rest.hasPrefix("gbit") {
                multiplier = 1e9
            } else if rest.hasPrefix("mbps") || rest.hasPrefix("mb/s") || rest.hasPrefix("mbit") {
                multiplier = 1e6
            } else if rest.hasPrefix("kbps") || rest.hasPrefix("kb/s") {
                multiplier = 1e3
            } else {
                multiplier = nil
            }
            if let multiplier, let value = Double(number), value.isFinite, value > 0, value < 1e6 {
                return Int64((value * multiplier).rounded())
            }
            i = j
        }
        return nil
    }

    /// The faster of two links. Unknown rates lose to known ones; on a tie
    /// the first argument is kept.
    static func faster(_ a: LinkInfo?, _ b: LinkInfo?) -> LinkInfo? {
        guard let a else { return b }
        guard let b else { return a }
        return (b.bitsPerSecond ?? -1) > (a.bitsPerSecond ?? -1) ? b : a
    }
}
