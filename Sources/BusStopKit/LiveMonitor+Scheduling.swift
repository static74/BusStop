import Dispatch
import Foundation

/// Decides when a requested capture runs. `LiveMonitor` owns one on its queue
/// and only does the cancelling and `asyncAfter` the answers call for, so the
/// coalescing rules can be tested with chosen times and no IOKit.
///
/// Urgent requests (start, poll ticks, `refreshNow`, the UI appearing) run as
/// soon as the queue is free. Other requests (IOKit, power-source and display
/// notifications) are debounced: each one pushes the capture back by the
/// debounce, but a burst never delays it by more than `burstLimit(debounce:)`
/// after the burst's first request. A pending capture always runs after the
/// request, so it also observes whatever change caused the request.
struct CaptureScheduler: Sendable, Equatable {
    /// Debounce used when the configured one is not a finite number.
    static let defaultDebounce: TimeInterval = 0.25
    /// Longest debounce accepted, in seconds.
    static let maximumDebounce: TimeInterval = 10
    /// A burst may always delay a capture by at least this long, in seconds.
    static let minimumBurstLimit: TimeInterval = 1
    /// A burst may delay a capture by this many debounce intervals.
    static let burstLimitMultiplier: Double = 4

    /// A capture is queued and has not started yet.
    private(set) var hasPending = false
    /// The queued capture was requested as urgent.
    private(set) var pendingIsUrgent = false
    /// When the first request of the current burst arrived.
    private(set) var burstStart: DispatchTime?

    /// `debounce` limited to `0...maximumDebounce`; `defaultDebounce` when it
    /// is not a finite number.
    static func clampedDebounce(_ debounce: TimeInterval) -> TimeInterval {
        guard debounce.isFinite else { return defaultDebounce }
        return min(maximumDebounce, max(0, debounce))
    }

    /// The longest a burst of requests may delay a capture, measured from the
    /// burst's first request.
    static func burstLimit(debounce: TimeInterval) -> TimeInterval {
        max(minimumBurstLimit, clampedDebounce(debounce) * burstLimitMultiplier)
    }

    /// Records a request made at `now`. Returns nil when the request needs no
    /// new work (an urgent capture is already queued and will observe the
    /// change). Otherwise returns the deadline of the capture that replaces
    /// any queued one.
    mutating func request(urgent: Bool, now: DispatchTime, debounce: TimeInterval) -> DispatchTime? {
        if hasPending && pendingIsUrgent {
            return nil
        }
        let deadline: DispatchTime
        if urgent {
            deadline = now
        } else {
            let start = burstStart ?? now
            burstStart = start
            let debounce = Self.clampedDebounce(debounce)
            deadline = min(now + debounce, start + Self.burstLimit(debounce: debounce))
        }
        hasPending = true
        pendingIsUrgent = urgent
        return deadline
    }

    /// The queued capture started: later requests schedule a new one and
    /// start a new burst.
    mutating func captureStarted() {
        self = CaptureScheduler()
    }
}

// MARK: - Poll timing

extension LiveMonitor {
    /// Shortest polling interval accepted, in seconds. The UI appearing does
    /// not capture again when a capture finished more recently than this.
    static let minimumPollInterval: TimeInterval = 0.5
    /// Longest polling interval accepted, in seconds.
    static let maximumPollInterval: TimeInterval = 3_600
    /// Polling interval used when the configured one is not a finite number.
    static let fallbackPollInterval: TimeInterval = 10

    /// `value` limited to `range`; `fallback` when it is not a finite number.
    static func clamp(_ value: TimeInterval, to range: ClosedRange<TimeInterval>,
                      fallback: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    /// The power polling interval for the UI's visibility, limited to
    /// `minimumPollInterval...maximumPollInterval`.
    static func pollInterval(visible: Bool, configuration: Configuration) -> TimeInterval {
        let requested = visible ? configuration.visibleInterval : configuration.backgroundInterval
        return clamp(requested, to: minimumPollInterval...maximumPollInterval, fallback: fallbackPollInterval)
    }

    /// When the next poll is due after the polling interval changes to
    /// `interval`. Measured from the last capture, so showing and hiding the
    /// UI in quick succession cannot keep pushing the poll back, and hiding it
    /// does not delay a poll that was nearly due. When a capture is about to
    /// run (`captureImminent`), or none has run yet, it is one interval from
    /// `now`. Never earlier than `now`.
    static func nextPollDeadline(now: DispatchTime, lastCapture: DispatchTime?, captureImminent: Bool,
                                 interval: TimeInterval) -> DispatchTime {
        guard !captureImminent, let lastCapture else { return now + interval }
        return max(now, lastCapture + interval)
    }

    /// Whether a visibility change should capture at once: only when the UI
    /// appears (hidden to visible), and not when a capture finished less than
    /// `minimumPollInterval` before `now`, since that one is still fresh.
    static func capturesOnVisibilityChange(wasVisible: Bool, visible: Bool, lastCapture: DispatchTime?,
                                           now: DispatchTime) -> Bool {
        guard visible && !wasVisible else { return false }
        guard let lastCapture else { return true }
        return now >= lastCapture + minimumPollInterval
    }
}
