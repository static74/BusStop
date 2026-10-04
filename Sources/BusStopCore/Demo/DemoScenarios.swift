import Foundation

/// Realistic sample setups for demo mode, screenshots, the CLI's `--demo`
/// flag and tests. Each produces a `RawSnapshot` so the whole pipeline runs.
///
/// The raw records use the IORegistry classes and keys real Macs publish
/// (see `DemoRegistry`), so `TopologyBuilder` reaches the intended topology
/// through the same code path as a live capture.
public enum DemoScenario: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    /// MacBook Pro 14" M5 Pro: Studio Display XDR over TB5 at 80 Gb/s with an
    /// SSD daisy-chained behind it, a USB-C hub with keyboard, mouse and a
    /// USB 3 flash drive stuck at USB 2 speed, 140 W MagSafe charger.
    case studioDesk
    /// MacBook Air 13" M4: 70 W USB-C charger, iPhone syncing at USB 2 speed.
    case travel
    /// Mac mini M4 Pro: Thunderbolt dock with Ethernet, audio interface,
    /// two drives and a card reader; front USB-C SSD; HDMI display.
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

    /// One line describing the setup, for pickers and the CLI.
    public var summary: String {
        switch self {
        case .studioDesk:
            return "MacBook Pro with a Studio Display XDR over Thunderbolt 5, a USB-C hub and a 140 W charger"
        case .travel:
            return "MacBook Air charging from a 70 W adapter while an iPhone syncs over a USB 2 cable"
        case .dockStation:
            return "Mac mini with a Thunderbolt 5 dock, a front SSD and an HDMI display"
        case .unplugged:
            return "MacBook Pro on battery with nothing plugged in"
        }
    }

    /// The `hw.model` the scenario describes.
    public var model: String {
        switch self {
        case .studioDesk: return DemoStudioDesk.model
        case .travel: return DemoTravel.model
        case .dockStation: return DemoDockStation.model
        case .unplugged: return DemoUnplugged.model
        }
    }

    /// The raw capture for this scenario. `date` stamps `capturedAt`;
    /// `tick` adds small deterministic variation to power readings so the
    /// sparklines move in demo mode. Everything else stays the same from
    /// tick to tick, and the same tick always gives the same capture.
    public func raw(at date: Date, tick: Int = 0) -> RawSnapshot {
        switch self {
        case .studioDesk: return DemoStudioDesk.raw(at: date, tick: tick)
        case .travel: return DemoTravel.raw(at: date, tick: tick)
        case .dockStation: return DemoDockStation.raw(at: date, tick: tick)
        case .unplugged: return DemoUnplugged.raw(at: date, tick: tick)
        }
    }
}
