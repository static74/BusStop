import Foundation

/// Which protocol family a link belongs to.
public enum LinkFamily: String, Sendable, Hashable, Codable, CaseIterable {
    case usb
    case thunderbolt
    case displayPort
    case hdmi
    case unknown
}

/// Coarse speed buckets used for colour and stroke width in the UI.
public enum SpeedTier: Int, Sendable, Hashable, Codable, Comparable, CaseIterable {
    /// Up to and including 480 Mb/s (USB 1.x / 2.0).
    case legacy = 0
    /// 5 Gb/s.
    case gbps5
    /// 10 Gb/s.
    case gbps10
    /// 20 Gb/s.
    case gbps20
    /// 40 Gb/s.
    case gbps40
    /// 80 Gb/s and faster (USB4 v2 / Thunderbolt 5, incl. 120 Gb/s boost).
    case gbps80

    public static func < (lhs: SpeedTier, rhs: SpeedTier) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(bitsPerSecond bps: Int64) {
        switch bps {
        case ..<1_000_000_000: self = .legacy
        case ..<9_000_000_000: self = .gbps5
        case ..<19_000_000_000: self = .gbps10
        case ..<39_000_000_000: self = .gbps20
        case ..<79_000_000_000: self = .gbps40
        default: self = .gbps80
        }
    }
}

/// A negotiated connection: protocol generation plus data rate.
///
/// `label` follows the ViewPorts style `"<generation> @ <rate>"`, for example
/// `"USB 3.2 Gen 2 @ 10 Gb/s"` or `"USB4 v2 / TB5 @ 80 Gb/s"`.
public struct LinkInfo: Sendable, Hashable, Codable {
    public var family: LinkFamily
    /// Human generation name: "USB 2.0", "USB 3.2 Gen 1", "USB 3.2 Gen 2",
    /// "USB 3.2 Gen 2x2", "Thunderbolt / USB4", "USB4 v2 / TB5",
    /// "DisplayPort", "HDMI".
    public var generation: String
    /// Total data rate in bits per second (sum over lanes), if known.
    public var bitsPerSecond: Int64?
    /// Number of lanes when meaningful (Thunderbolt, DisplayPort).
    public var lanes: Int?
    /// Thunderbolt 5 asymmetric mode (e.g. 120 Gb/s one way, 40 the other).
    public var isAsymmetric: Bool
    /// Extra detail, e.g. "HBR3 × 4" for DisplayPort, "2 × 40 Gb/s" for TB.
    public var detail: String?

    public init(family: LinkFamily, generation: String, bitsPerSecond: Int64? = nil, lanes: Int? = nil,
                isAsymmetric: Bool = false, detail: String? = nil) {
        self.family = family
        self.generation = generation
        self.bitsPerSecond = bitsPerSecond
        self.lanes = lanes
        self.isAsymmetric = isAsymmetric
        self.detail = detail
    }

    public var tier: SpeedTier {
        bitsPerSecond.map(SpeedTier.init(bitsPerSecond:)) ?? .legacy
    }

    /// `"10 Gb/s"`, `"480 Mb/s"`; nil when the rate is unknown.
    public var rateLabel: String? {
        bitsPerSecond.map(Format.dataRate(bitsPerSecond:))
    }

    /// `"USB 3.2 Gen 2 @ 10 Gb/s"`, or just the generation when the rate is unknown.
    public var label: String {
        if let rate = rateLabel { return "\(generation) @ \(rate)" }
        return generation
    }
}
