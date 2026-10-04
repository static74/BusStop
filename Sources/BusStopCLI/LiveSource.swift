import BusStopCore
import BusStopKit
import Foundation

/// The CLI's only contact with IOKit. Everything else in the tool works on
/// `RawSnapshot` values, so it behaves the same for live, demo and file input.
enum LiveSource {
    /// One full capture of this Mac.
    static func capture(includeSMC: Bool) -> RawSnapshot {
        RegistryCapture.capture(includeSMC: includeSMC)
    }

    /// Starts live monitoring. `onSnapshot` runs on the main actor after every
    /// capture, starting with one right away.
    ///
    /// - Returns: a function that stops monitoring.
    static func startMonitoring(
        includeSMC: Bool,
        onSnapshot: @escaping @MainActor @Sendable (RawSnapshot) -> Void
    ) -> @Sendable () -> Void {
        let monitor = LiveMonitor(configuration: LiveMonitor.Configuration(includeSMC: includeSMC))
        monitor.start(onSnapshot: onSnapshot)
        return { monitor.stop() }
    }
}
