import Foundation

/// Realistic sample setups for demo mode, screenshots, the CLI's `--demo`
/// flag and tests. Each produces a `RawSnapshot` so the whole pipeline runs.
public enum DemoScenario: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    /// MacBook Pro 14" M5 Pro: Studio Display XDR over TB5 at 80 Gb/s with an
    /// SSD daisy-chained behind it, a USB-C hub with keyboard, mouse and a
    /// USB 2 flash drive, 140 W MagSafe charger.
    case studioDesk
    /// MacBook Air 13" M4: 70 W USB-C charger, iPhone syncing at USB 2 speed.
    case travel
    /// Mac mini M4 Pro: Thunderbolt dock with Ethernet, audio interface,
    /// two drives; front USB-C SSD; HDMI display.
    case dockStation
    /// MacBook Pro with nothing plugged in, on battery.
    case unplugged

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .studioDesk: return "Studio desk"
        case .travel: return "Travel"
        case .dockStation: return "Dock station"
        case .unplugged: return "Unplugged"
        }
    }

    /// The raw capture for this scenario. `date` stamps `capturedAt`;
    /// `tick` adds small deterministic variation to power readings so the
    /// sparklines move in demo mode.
    public func raw(at date: Date, tick: Int = 0) -> RawSnapshot {
        RawSnapshot(capturedAt: date,
                    machine: MachineInfo(model: "Mac16,6", chip: "Apple M5 Pro", osVersion: "27.0", hasBattery: true))
    }
}
