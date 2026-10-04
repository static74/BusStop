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
}
