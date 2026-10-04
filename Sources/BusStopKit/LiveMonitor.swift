import BusStopCore
import Foundation

/// Watches IOKit, power sources and displays, and produces a new
/// `RawSnapshot` whenever something changes, plus periodic power refreshes.
///
/// All IOKit work runs on one private serial queue. Snapshots are delivered on
/// the main actor.
public final class LiveMonitor: @unchecked Sendable {
    public struct Configuration: Sendable, Hashable {
        /// Power polling interval while a Bus Stop window or popover is visible.
        public var visibleInterval: TimeInterval
        /// Power polling interval otherwise (keeps the menu bar text fresh).
        public var backgroundInterval: TimeInterval
        /// Coalescing delay for bursts of IOKit notifications.
        public var debounce: TimeInterval
        /// Read per-port power from the SMC.
        public var includeSMC: Bool

        public init(visibleInterval: TimeInterval = 2, backgroundInterval: TimeInterval = 10,
                    debounce: TimeInterval = 0.25, includeSMC: Bool = true) {
            self.visibleInterval = visibleInterval
            self.backgroundInterval = backgroundInterval
            self.debounce = debounce
            self.includeSMC = includeSMC
        }
    }

    public init(configuration: Configuration = Configuration()) {
        fatalError("not implemented")
    }

    /// Starts notifications and polling, and captures once immediately.
    /// `onSnapshot` runs on the main actor after every capture.
    public func start(onSnapshot: @escaping @MainActor @Sendable (RawSnapshot) -> Void) {
        fatalError("not implemented")
    }

    /// Stops notifications and polling. Safe to call more than once.
    public func stop() {
        fatalError("not implemented")
    }

    /// Captures as soon as possible (still coalesced with pending work).
    public func refreshNow() {
        fatalError("not implemented")
    }

    /// Switches between the visible and background polling intervals.
    public func setUIVisible(_ visible: Bool) {
        fatalError("not implemented")
    }

    public func update(configuration: Configuration) {
        fatalError("not implemented")
    }
}
