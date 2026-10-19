import BusStopCore
import Foundation
import Testing
@testable import BusStopKit

/// Collects delivered snapshots on the main actor.
@MainActor
final class SnapshotRecorder {
    var snapshots: [RawSnapshot] = []
}

@Suite("LiveMonitor", .serialized)
@MainActor
struct LiveMonitorTests {
    private static let configuration = LiveMonitor.Configuration(
        visibleInterval: 1, backgroundInterval: 1, debounce: 0.1, includeSMC: false
    )

    /// Waits on the main actor until `condition` holds or `timeout` passes.
    private func wait(timeout: TimeInterval, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func deliversSnapshotsAndStopsCleanly() async throws {
        let monitor = LiveMonitor(configuration: Self.configuration)
        let recorder = SnapshotRecorder()
        monitor.start { raw in recorder.snapshots.append(raw) }

        try await wait(timeout: 10) { !recorder.snapshots.isEmpty }
        #expect(!recorder.snapshots.isEmpty)
        #expect(recorder.snapshots.first.map { !$0.machine.model.isEmpty } == true)

        let running = monitor.registrations
        #expect(running.isRunning)
        #expect(running.hasPollTimer)
        #expect(running.hasNotificationPort)
        #expect(running.matchIterators == LiveMonitor.matchedClasses.count * 2)
        print("BUSSTOP-MONITOR registrations=\(running) captures=\(monitor.completedCaptures)")

        // A second start replaces the handler but registers nothing twice.
        monitor.start { raw in recorder.snapshots.append(raw) }
        let restarted = monitor.registrations
        #expect(restarted.matchIterators == running.matchIterators)
        #expect(restarted.hasPollTimer)

        // Polling keeps delivering.
        let countBefore = recorder.snapshots.count
        try await wait(timeout: 10) { recorder.snapshots.count > countBefore }
        #expect(recorder.snapshots.count > countBefore)

        monitor.stop()
        let stopped = monitor.registrations
        #expect(!stopped.isRunning)
        #expect(stopped.matchIterators == 0)
        #expect(stopped.interestNotifications == 0)
        #expect(!stopped.hasNotificationPort)
        #expect(!stopped.hasPollTimer)
        #expect(!stopped.hasPowerSourceNotification)

        // Nothing is delivered after stop, even from a capture already queued.
        let countAtStop = recorder.snapshots.count
        try await Task.sleep(for: .milliseconds(2_500))
        #expect(recorder.snapshots.count == countAtStop)

        monitor.stop()
        #expect(!monitor.registrations.isRunning)
    }

    @Test func refreshNowAndRestart() async throws {
        let monitor = LiveMonitor(configuration: LiveMonitor.Configuration(
            visibleInterval: 30, backgroundInterval: 30, debounce: 0.1, includeSMC: false
        ))
        let recorder = SnapshotRecorder()
        monitor.setUIVisible(true)
        monitor.start { raw in recorder.snapshots.append(raw) }
        try await wait(timeout: 10) { !recorder.snapshots.isEmpty }
        #expect(recorder.snapshots.count >= 1)

        let count = recorder.snapshots.count
        monitor.refreshNow()
        try await wait(timeout: 10) { recorder.snapshots.count > count }
        #expect(recorder.snapshots.count > count)

        monitor.update(configuration: Self.configuration)
        monitor.setUIVisible(false)
        monitor.stop()

        // Start again after a stop.
        let restartCount = recorder.snapshots.count
        monitor.start { raw in recorder.snapshots.append(raw) }
        try await wait(timeout: 10) { recorder.snapshots.count > restartCount }
        #expect(recorder.snapshots.count > restartCount)
        monitor.stop()
    }

    @Test func showingTheUICapturesAtOnce() async throws {
        // Polls far apart, so only showing the UI can cause the capture.
        let monitor = LiveMonitor(configuration: LiveMonitor.Configuration(
            visibleInterval: 30, backgroundInterval: 30, debounce: 0.1, includeSMC: false
        ))
        let recorder = SnapshotRecorder()
        monitor.start { raw in recorder.snapshots.append(raw) }
        try await wait(timeout: 10) { !recorder.snapshots.isEmpty }
        // Let the start-up capture age past the window in which it counts as fresh.
        try await Task.sleep(for: .milliseconds(800))

        let count = monitor.completedCaptures
        monitor.setUIVisible(true)
        try await wait(timeout: 5) { monitor.completedCaptures > count }
        #expect(monitor.completedCaptures > count)
        monitor.stop()
    }

    @Test func burstOfChangesCoalescesIntoOneCapture() async throws {
        let monitor = LiveMonitor(configuration: LiveMonitor.Configuration(
            visibleInterval: 30, backgroundInterval: 30, debounce: 0.1, includeSMC: false
        ))
        let recorder = SnapshotRecorder()
        monitor.start { raw in recorder.snapshots.append(raw) }
        try await wait(timeout: 10) { !recorder.snapshots.isEmpty }
        try await Task.sleep(for: .milliseconds(300))

        let before = monitor.completedCaptures
        for _ in 0..<20 {
            monitor.externalChangeFromAnyThread()
        }
        try await wait(timeout: 5) { monitor.completedCaptures > before }
        // Time for any extra capture the burst should not cause.
        try await Task.sleep(for: .milliseconds(1_200))
        let captures = monitor.completedCaptures - before
        print("BUSSTOP-MONITOR burst of 20 changes -> \(captures) capture(s)")
        // One capture for the burst. A second one is tolerated in case the
        // runner reports a real hardware or power change meanwhile.
        #expect(captures >= 1)
        #expect(captures <= 2)
        monitor.stop()
    }

    @Test func powerChangesReuseTheTopologyAndHardwareChangesDoNot() async throws {
        let monitor = LiveMonitor(configuration: LiveMonitor.Configuration(
            visibleInterval: 30, backgroundInterval: 30, debounce: 0.1, includeSMC: false
        ))
        let recorder = SnapshotRecorder()
        monitor.start { raw in recorder.snapshots.append(raw) }
        try await wait(timeout: 10) { !recorder.snapshots.isEmpty }
        #expect(monitor.completedFullCaptures == 1)

        // Real battery interest may add power-only captures meanwhile, so
        // only the count of power-only captures going up is checked.
        let powerOnly = monitor.completedCaptures - monitor.completedFullCaptures
        monitor.powerChangeFromAnyThread()
        try await wait(timeout: 5) { monitor.completedCaptures - monitor.completedFullCaptures > powerOnly }
        #expect(monitor.completedCaptures - monitor.completedFullCaptures > powerOnly)
        #expect(recorder.snapshots.last?.portNodes == recorder.snapshots.first?.portNodes)

        let full = monitor.completedFullCaptures
        monitor.externalChangeFromAnyThread()
        try await wait(timeout: 5) { monitor.completedFullCaptures > full }
        #expect(monitor.completedFullCaptures > full)
        monitor.stop()
    }

    @Test func anyCapturePushesThePollBack() async throws {
        // A power change every 0.5 s, more often than the 1.5 s poll: the
        // poll never comes due because each capture re-arms it.
        let monitor = LiveMonitor(configuration: LiveMonitor.Configuration(
            visibleInterval: 1.5, backgroundInterval: 1.5, debounce: 0.05, includeSMC: false
        ))
        let recorder = SnapshotRecorder()
        monitor.start { raw in recorder.snapshots.append(raw) }
        try await wait(timeout: 10) { !recorder.snapshots.isEmpty }
        let ticks = monitor.pollTicks
        for _ in 0..<8 {
            monitor.powerChangeFromAnyThread()
            try await Task.sleep(for: .milliseconds(500))
        }
        #expect(monitor.pollTicks == ticks)

        // With the changes gone, polling resumes.
        try await wait(timeout: 5) { monitor.pollTicks > ticks }
        #expect(monitor.pollTicks > ticks)
        monitor.stop()
    }

    @Test func pausedPollingIgnoresPowerChangesUntilResumed() async throws {
        let monitor = LiveMonitor(configuration: Self.configuration)
        let recorder = SnapshotRecorder()
        monitor.start { raw in recorder.snapshots.append(raw) }
        try await wait(timeout: 10) { !recorder.snapshots.isEmpty }

        monitor.setPollingPaused(true)
        #expect(!monitor.registrations.hasPollTimer)
        #expect(monitor.registrations.hasNotificationPort)
        let powerOnly = monitor.completedCaptures - monitor.completedFullCaptures
        let ticks = monitor.pollTicks
        for _ in 0..<3 { monitor.powerChangeFromAnyThread() }
        try await Task.sleep(for: .milliseconds(1_500))
        #expect(monitor.completedCaptures - monitor.completedFullCaptures == powerOnly)
        #expect(monitor.pollTicks == ticks)

        // Waking captures the whole topology at once and polls again.
        let full = monitor.completedFullCaptures
        monitor.setPollingPaused(false)
        try await wait(timeout: 5) { monitor.completedFullCaptures > full }
        #expect(monitor.completedFullCaptures > full)
        #expect(monitor.registrations.hasPollTimer)
        try await wait(timeout: 5) { monitor.pollTicks > ticks }
        #expect(monitor.pollTicks > ticks)
        monitor.stop()
    }

    @Test func rapidStartStopCyclesDeliverNothingAfterStop() async throws {
        let recorder = SnapshotRecorder()
        for _ in 0..<10 {
            let monitor = LiveMonitor(configuration: Self.configuration)
            monitor.start { raw in recorder.snapshots.append(raw) }
            monitor.refreshNow()
            monitor.setUIVisible(true)
            monitor.stop()
            #expect(monitor.registrations == LiveMonitor.Registrations(
                isRunning: false, matchIterators: 0, interestNotifications: 0,
                hasNotificationPort: false, hasPollTimer: false, hasPowerSourceNotification: false
            ))
        }
        // Each monitor was stopped before the main actor could run any
        // delivery it queued, so every delivery is dropped.
        try await Task.sleep(for: .milliseconds(1_000))
        #expect(recorder.snapshots.isEmpty)
    }

    @Test func releasingTheMonitorTearsDown() async throws {
        var monitor: LiveMonitor? = LiveMonitor(configuration: Self.configuration)
        let recorder = SnapshotRecorder()
        monitor?.start { raw in recorder.snapshots.append(raw) }
        try await wait(timeout: 10) { !recorder.snapshots.isEmpty }
        monitor = nil
        let count = recorder.snapshots.count
        try await Task.sleep(for: .milliseconds(1_500))
        #expect(recorder.snapshots.count == count)
    }
}
