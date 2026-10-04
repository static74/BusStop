import Dispatch
import Foundation
import Testing
@testable import BusStopKit

/// The scheduling decisions behind `LiveMonitor`, driven with chosen times.
@Suite("Capture scheduling")
struct CaptureSchedulerTests {
    /// An arbitrary uptime well away from zero (zero means "now" to Dispatch).
    private static let base = DispatchTime(uptimeNanoseconds: 1_000_000_000_000)

    /// `seconds` after `base`.
    private func at(_ seconds: Double) -> DispatchTime { Self.base + seconds }

    // MARK: Coalescing

    @Test func burstOfChangesGivesOneCaptureWithinTheBurstLimit() throws {
        var scheduler = CaptureScheduler()
        var deadlines: [DispatchTime] = []
        // Ten changes 0.1 s apart, closer together than the 0.25 s debounce.
        for step in 0..<10 {
            let now = at(Double(step) * 0.1)
            let request = scheduler.request(urgent: false, now: now, debounce: 0.25)
            let deadline = try #require(request)
            #expect(deadline >= now)
            #expect(deadline <= now + 0.25)
            deadlines.append(deadline)
        }
        // Each change replaced the queued capture and pushed it back, but
        // never past one second after the first change.
        #expect(deadlines.first == at(0) + 0.25)
        #expect(zip(deadlines, deadlines.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(deadlines.allSatisfy { $0 <= at(0) + 1.0 })
        #expect(deadlines.last == at(0) + 1.0)
        #expect(scheduler.hasPending)
        #expect(!scheduler.pendingIsUrgent)
        #expect(scheduler.burstStart == at(0))
    }

    @Test(arguments: [0.05, 0.1, 0.25, 0.5, 2.0])
    func burstLimitHoldsForAnyDebounce(debounce: TimeInterval) throws {
        var scheduler = CaptureScheduler()
        let limit = CaptureScheduler.burstLimit(debounce: debounce)
        #expect(limit == max(1, debounce * 4))
        let spacing = debounce * 0.8
        var elapsed = 0.0
        var last: DispatchTime?
        while elapsed < limit {
            let now = at(elapsed)
            let request = scheduler.request(urgent: false, now: now, debounce: debounce)
            let deadline = try #require(request)
            #expect(deadline >= now)
            #expect(deadline <= at(0) + limit)
            last = deadline
            elapsed += spacing
        }
        #expect(last == at(0) + limit)
    }

    @Test func urgentRequestReplacesADebouncedCapture() {
        var scheduler = CaptureScheduler()
        let debounced = scheduler.request(urgent: false, now: at(0), debounce: 0.25)
        #expect(debounced == at(0) + 0.25)
        let urgent = scheduler.request(urgent: true, now: at(0.1), debounce: 0.25)
        #expect(urgent == at(0.1))
        #expect(scheduler.hasPending)
        #expect(scheduler.pendingIsUrgent)
    }

    @Test func requestsWhileAnUrgentCaptureIsQueuedAreIgnored() {
        var scheduler = CaptureScheduler()
        let urgent = scheduler.request(urgent: true, now: at(0), debounce: 0.25)
        #expect(urgent == at(0))
        let debouncedLater = scheduler.request(urgent: false, now: at(0.01), debounce: 0.25)
        #expect(debouncedLater == nil)
        let urgentLater = scheduler.request(urgent: true, now: at(0.02), debounce: 0.25)
        #expect(urgentLater == nil)
        #expect(scheduler.hasPending)
        #expect(scheduler.pendingIsUrgent)
    }

    @Test func captureStartedOpensANewBurst() throws {
        var scheduler = CaptureScheduler()
        _ = scheduler.request(urgent: false, now: at(0), debounce: 0.25)
        _ = scheduler.request(urgent: true, now: at(0.1), debounce: 0.25)
        scheduler.captureStarted()
        #expect(scheduler == CaptureScheduler())

        // A change seen while the capture runs schedules another capture,
        // and the burst limit counts from that change, not from the old burst.
        var last: DispatchTime?
        for step in 0..<5 {
            let request = scheduler.request(urgent: false, now: at(0.6 + Double(step) * 0.2), debounce: 0.25)
            let deadline = try #require(request)
            last = deadline
        }
        #expect(scheduler.burstStart == at(0.6))
        #expect(last == at(0.6) + 1.0)
        let lastDeadline = try #require(last)
        #expect(lastDeadline > at(0) + 1.0)

        // After an urgent capture starts, urgent requests schedule again too.
        scheduler.captureStarted()
        _ = scheduler.request(urgent: true, now: at(2), debounce: 0.25)
        scheduler.captureStarted()
        let again = scheduler.request(urgent: true, now: at(2.5), debounce: 0.25)
        #expect(again == at(2.5))
    }

    @Test func debounceIsClamped() {
        #expect(CaptureScheduler.clampedDebounce(.nan) == CaptureScheduler.defaultDebounce)
        #expect(CaptureScheduler.clampedDebounce(.infinity) == CaptureScheduler.defaultDebounce)
        #expect(CaptureScheduler.clampedDebounce(-.infinity) == CaptureScheduler.defaultDebounce)
        #expect(CaptureScheduler.clampedDebounce(-1) == 0)
        #expect(CaptureScheduler.clampedDebounce(0.1) == 0.1)
        #expect(CaptureScheduler.clampedDebounce(60) == CaptureScheduler.maximumDebounce)
        #expect(CaptureScheduler.burstLimit(debounce: -1) == 1)
        #expect(CaptureScheduler.burstLimit(debounce: .nan) == 1)
        #expect(CaptureScheduler.burstLimit(debounce: 60) == CaptureScheduler.maximumDebounce * 4)

        // The clamped value is the one the deadline uses.
        var scheduler = CaptureScheduler()
        let notANumber = scheduler.request(urgent: false, now: at(0), debounce: .nan)
        #expect(notANumber == at(0) + 0.25)
        scheduler.captureStarted()
        let negative = scheduler.request(urgent: false, now: at(0), debounce: -5)
        #expect(negative == at(0) + 0.0)
        scheduler.captureStarted()
        let tooLong = scheduler.request(urgent: false, now: at(0), debounce: 1_000)
        #expect(tooLong == at(0) + 10.0)
    }

    // MARK: Polling

    @Test func pollIntervalFollowsVisibilityAndIsClamped() {
        let normal = LiveMonitor.Configuration(visibleInterval: 2, backgroundInterval: 10)
        #expect(LiveMonitor.pollInterval(visible: true, configuration: normal) == 2)
        #expect(LiveMonitor.pollInterval(visible: false, configuration: normal) == 10)

        let extreme = LiveMonitor.Configuration(visibleInterval: 0.01, backgroundInterval: 1_000_000)
        #expect(LiveMonitor.pollInterval(visible: true, configuration: extreme) == LiveMonitor.minimumPollInterval)
        #expect(LiveMonitor.pollInterval(visible: false, configuration: extreme) == LiveMonitor.maximumPollInterval)

        let invalid = LiveMonitor.Configuration(visibleInterval: .nan, backgroundInterval: -3)
        #expect(LiveMonitor.pollInterval(visible: true, configuration: invalid) == LiveMonitor.fallbackPollInterval)
        #expect(LiveMonitor.pollInterval(visible: false, configuration: invalid) == LiveMonitor.minimumPollInterval)
    }

    @Test func pollDeadlineCountsFromTheLastCapture() {
        // No capture yet, or one about to run: one interval from now.
        #expect(LiveMonitor.nextPollDeadline(now: at(5), lastCapture: nil, captureImminent: false, interval: 2)
                == at(5) + 2)
        #expect(LiveMonitor.nextPollDeadline(now: at(5), lastCapture: at(4), captureImminent: true, interval: 2)
                == at(5) + 2)
        // Otherwise one interval after the last capture, so hiding the UI
        // does not delay a background poll that was nearly due...
        #expect(LiveMonitor.nextPollDeadline(now: at(5), lastCapture: at(4), captureImminent: false, interval: 10)
                == at(4) + 10)
        // ...and never in the past.
        #expect(LiveMonitor.nextPollDeadline(now: at(5), lastCapture: at(1), captureImminent: false, interval: 2)
                == at(5))
    }

    @Test func onlyShowingTheUICapturesAtOnce() {
        let now = at(10)
        #expect(LiveMonitor.capturesOnVisibilityChange(wasVisible: false, visible: true, lastCapture: nil, now: now))
        #expect(LiveMonitor.capturesOnVisibilityChange(wasVisible: false, visible: true, lastCapture: at(8), now: now))
        // A capture that just finished is fresh enough.
        #expect(!LiveMonitor.capturesOnVisibilityChange(wasVisible: false, visible: true, lastCapture: at(9.8),
                                                       now: now))
        // A second window appearing, or the UI hiding, does not capture.
        #expect(!LiveMonitor.capturesOnVisibilityChange(wasVisible: true, visible: true, lastCapture: at(1), now: now))
        #expect(!LiveMonitor.capturesOnVisibilityChange(wasVisible: true, visible: false, lastCapture: at(1), now: now))
        #expect(!LiveMonitor.capturesOnVisibilityChange(wasVisible: false, visible: false, lastCapture: at(1),
                                                       now: now))
    }

    /// Quick popover glances used to re-phase the poll timer on every change
    /// without capturing, so neither the visible nor the background deadline
    /// was ever reached and power values froze.
    @Test(arguments: [0.3, 0.4, 1.0, 1.9])
    func quickGlancesKeepPowerValuesFresh(glance: TimeInterval) throws {
        let configuration = LiveMonitor.Configuration(visibleInterval: 2, backgroundInterval: 10)
        var toggles: [(time: Double, visible: Bool)] = []
        var time = glance
        while time < 60 {
            toggles.append((time, true))
            toggles.append((time + glance, false))
            time += glance * 2
        }
        let captures = simulate(toggles: toggles, until: 60, configuration: configuration)

        // Every glance shows a capture under half a second old.
        for toggle in toggles where toggle.visible {
            let now = at(toggle.time)
            #expect(captures.contains { $0 <= now && now < $0 + LiveMonitor.minimumPollInterval })
        }
        // Captures are never further apart than the background interval.
        for (earlier, later) in zip(captures, captures.dropFirst()) {
            #expect(later <= earlier + 10)
        }
        #expect(try #require(captures.last) + 10 >= at(60))
    }

    @Test func pollsKeepTheirCadenceWhileTheUIStaysVisible() {
        let configuration = LiveMonitor.Configuration(visibleInterval: 2, backgroundInterval: 10)
        let captures = simulate(toggles: [(5, true), (20, false)], until: 40, configuration: configuration)
        // Start-up capture at 0. The UI appears at 5 s and captures then,
        // polls every 2 s from that capture, and once it hides the next
        // background poll is 10 s after the last capture.
        let expected: [Double] = [0, 5, 7, 9, 11, 13, 15, 17, 19, 29, 39]
        #expect(captures == expected.map { at($0) })
    }

    /// Replays visibility changes against the poll policy the way
    /// `LiveMonitor` applies it, with captures taking no time. Returns the
    /// capture times, starting with the one `start()` makes at zero.
    private func simulate(toggles: [(time: Double, visible: Bool)], until end: Double,
                          configuration: LiveMonitor.Configuration) -> [DispatchTime] {
        var visible = false
        var interval = LiveMonitor.pollInterval(visible: visible, configuration: configuration)
        var captures = [at(0)]
        var timer = at(0) + interval

        func runTimer(until now: DispatchTime) {
            while timer <= now {
                captures.append(timer)
                timer = timer + interval
            }
        }

        for toggle in toggles {
            let now = at(toggle.time)
            runTimer(until: now)
            let capturesNow = LiveMonitor.capturesOnVisibilityChange(
                wasVisible: visible, visible: toggle.visible, lastCapture: captures.last, now: now
            )
            visible = toggle.visible
            let newInterval = LiveMonitor.pollInterval(visible: visible, configuration: configuration)
            if newInterval != interval {
                interval = newInterval
                timer = LiveMonitor.nextPollDeadline(now: now, lastCapture: captures.last,
                                                     captureImminent: capturesNow, interval: interval)
            }
            if capturesNow {
                captures.append(now)
            }
        }
        runTimer(until: at(end))
        return captures
    }
}
