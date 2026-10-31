import AppKit
import BusStopUI
import SwiftUI

/// The interface's colours as chosen in Settings › Appearance › Colour: a
/// preset, or the preset nearest the system accent colour.
enum DataColorSetting: Hashable, Identifiable {
    case system
    case preset(DataPalette)

    static let allCases: [DataColorSetting] = [.system] + DataPalette.allCases.map(DataColorSetting.preset)

    init?(rawValue: String) {
        if rawValue == "system" {
            self = .system
        } else if let palette = DataPalette(rawValue: rawValue) {
            self = .preset(palette)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .system: return "system"
        case .preset(let palette): return palette.rawValue
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Match System"
        case .preset(let palette): return palette.title
        }
    }

    /// The palette to draw with; `system` is the system accent's preset.
    func resolved(system: @autoclosure () -> DataPalette) -> DataPalette {
        switch self {
        case .system: return system()
        case .preset(let palette): return palette
        }
    }
}

/// The preset nearest the macOS accent colour, kept current as it changes in
/// System Settings › Appearance.
@Observable
final class SystemAccentPalette {
    static let shared = SystemAccentPalette()

    private(set) var palette = DataPalette.nearest(to: .controlAccentColor)

    private init() {
        NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.palette = DataPalette.nearest(to: .controlAccentColor) }
        }
    }
}

extension DataColorSetting {
    /// Keeps `LagoonTheme.shared` on the preset `settings` asks for: now, and
    /// again whenever the setting or the system accent changes. Call once at launch.
    static func follow(_ settings: AppSettings) {
        let palette = withObservationTracking {
            settings.dataColor.resolved(system: SystemAccentPalette.shared.palette)
        } onChange: {
            Task { @MainActor in follow(settings) }
        }
        guard LagoonTheme.shared.palette != palette else { return }
        LagoonTheme.shared.palette = palette
        // AppKit keeps the window background it was given.
        WindowManager.shared.applyBackground()
    }
}

extension View {
    /// Sets the active preset's map colours for everything below (use at view
    /// roots). It reads `LagoonTheme`, so the map's colours and the rest of
    /// the interface always change together.
    func dataPalette() -> some View {
        environment(\.dataPalette, LagoonTheme.shared.palette)
    }
}
