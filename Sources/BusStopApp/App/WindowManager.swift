import AppKit
import BusStopCore
import SwiftUI

/// Opens and tracks the app's windows (topology, settings, about) and handles
/// the accessory-app activation dance. Placeholder; implemented by the app shell.
final class WindowManager {
    static let shared = WindowManager()

    /// Set once at launch by the app delegate.
    var store: PortStore?

    func showTopology(selecting selection: StoreSelection? = nil) {}
    func showSettings(tab: SettingsTab? = nil) {}
    func showAbout() {}
}
