// Portions adapted from WhatPort (MIT License, © 2025 Darryl Morley).

import BusStopCore
import CoreGraphics
import Foundation
import IOKit
import IOKit.ps
import os
#if canImport(notify)
import notify
#endif

/// Watches IOKit, power sources and displays, and produces a new
/// `RawSnapshot` whenever something changes, plus periodic power refreshes.
///
/// All IOKit work runs on one private serial queue. Snapshots are delivered on
/// the main actor.
///
/// Threading: every mutable property below is touched only on `queue`. The
/// IOKit notification port and the power-source notification deliver on that
/// queue, so their callbacks never race with `start()` / `stop()`, which run
/// their work on the queue synchronously. Captures also run on the queue, so
/// two captures never overlap. Display reconfiguration callbacks arrive on
/// the main thread and only post work to the queue.
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

    /// Classes watched for services appearing and terminating.
    static let matchedClasses = [
        "IOUSBHostDevice", "IOAccessoryManager", "IOPort",
        "IOPortTransportStateCC", "IOPortTransportStateUSB2", "IOPortTransportStateUSB3",
        "IOPortTransportStateDisplayPort", "IOPortTransportStateCIO", "IOPortFeaturePowerSource",
        "IOThunderboltSwitch", "IOIOThunderboltSwitch",
    ]

    /// Services of these classes also get property-change (general interest)
    /// notifications: plugging a cable into an empty port only flips
    /// properties on the port controller and its CC transport.
    static let interestClasses = [
        "IOAccessoryManager", "IOPort", "IOPortTransportStateCC", "IOPortFeaturePowerSource",
    ]

    /// The `notify(3)` name posted when the power source changes
    /// (`kIOPSNotifyPowerSource`).
    static let powerSourceNotification = "com.apple.system.powersources.source"

    private let queue = DispatchQueue(label: "app.busstop.live-monitor", qos: .utility)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let gate = DeliveryGate()
    private let smc = SMCReader()

    // MARK: Queue-confined state

    private var configuration: Configuration
    private var uiVisible = false
    private var handler: (@MainActor @Sendable (RawSnapshot) -> Void)?
    /// Delivery generation of the current run (see `DeliveryGate`).
    private var generation: UInt64 = 0
    private var isRunning = false
    /// True while `start()` drains the initial matches, so they do not each
    /// schedule a capture.
    private var isArming = false
    /// IOKit and `notify` registrations of the current run.
    private var notifications: NotificationRegistrations?
    /// Context passed to main-thread callbacks (displays, power-source run
    /// loop source). Released on the main thread after removal.
    private var mainThreadBox: CallbackBox?
    private var pollTimer: DispatchSourceTimer?
    private var pollInterval: TimeInterval?
    private var pendingCapture: DispatchWorkItem?
    /// Coalescing state of `pendingCapture` (see `CaptureScheduler`).
    private var scheduler = CaptureScheduler()
    private var captureCount = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        gate.advance()
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            // The last reference went away inside work running on the queue,
            // possibly an IOKit callback. Release the notification port only
            // after that work returns, never from inside its own callback.
            let detached = notifications
            notifications = nil
            teardown()
            queue.async { detached?.release() }
        } else {
            queue.sync { teardown() }
        }
    }

    // MARK: Public API

    /// Starts notifications and polling, and captures once immediately.
    /// `onSnapshot` runs on the main actor after every capture. Calling
    /// `start` again while running replaces the handler without registering
    /// anything twice.
    public func start(onSnapshot: @escaping @MainActor @Sendable (RawSnapshot) -> Void) {
        let generation = gate.advance()
        performSync {
            self.handler = onSnapshot
            self.generation = generation
            if !self.isRunning {
                self.isRunning = true
                self.register()
            }
            self.scheduleCapture(urgent: true)
        }
    }

    /// Stops notifications and polling. Safe to call more than once. After it
    /// returns no IOKit callback runs and no further snapshot is delivered.
    public func stop() {
        gate.advance()
        performSync { self.teardown() }
    }

    /// Captures as soon as possible (still coalesced with pending work).
    public func refreshNow() {
        queue.async { [weak self] in self?.scheduleCapture(urgent: true) }
    }

    /// Switches between the visible and background polling intervals.
    public func setUIVisible(_ visible: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.uiVisible = visible
            self.updatePollTimer()
        }
    }

    public func update(configuration: Configuration) {
        queue.async { [weak self] in
            guard let self else { return }
            self.configuration = configuration
            self.updatePollTimer()
        }
    }

    // MARK: Introspection (tests)

    /// What is currently registered.
    struct Registrations: Equatable {
        var isRunning: Bool
        var matchIterators: Int
        var interestNotifications: Int
        var hasNotificationPort: Bool
        var hasPollTimer: Bool
        var hasPowerSourceNotification: Bool
    }

    var registrations: Registrations {
        performSync {
            Registrations(
                isRunning: isRunning,
                matchIterators: notifications?.matchIterators.count ?? 0,
                interestNotifications: notifications?.interest.count ?? 0,
                hasNotificationPort: notifications?.port != nil,
                hasPollTimer: pollTimer != nil,
                hasPowerSourceNotification: notifications?.powerToken != nil
            )
        }
    }

    /// Number of captures run since the monitor was created.
    var completedCaptures: Int { performSync { captureCount } }

    /// How power-source changes are observed in this build.
    static var powerSourceMechanism: String {
        #if canImport(notify)
        return "notify_register_dispatch"
        #else
        return "IOPSNotificationCreateRunLoopSource"
        #endif
    }

    // MARK: Registration (on queue)

    private func register() {
        let registrations = NotificationRegistrations(box: CallbackBox(monitor: self))
        notifications = registrations

        if let port = IONotificationPortCreate(kIOMainPortDefault) {
            IONotificationPortSetDispatchQueue(port, queue)
            registrations.port = port
            let refcon = Unmanaged.passUnretained(registrations.box).toOpaque()
            isArming = true
            for className in Self.matchedClasses {
                addMatchingNotification(port: port, className: className, terminated: false, refcon: refcon)
                addMatchingNotification(port: port, className: className, terminated: true, refcon: refcon)
            }
            if let battery = RegistryEntry.firstMatching(className: "AppleSmartBattery") {
                addInterest(battery)
            }
            isArming = false
        }

        registerPowerSourceNotification()
        registerMainThreadCallbacks()
        updatePollTimer()
    }

    private func addMatchingNotification(port: IONotificationPortRef, className: String, terminated: Bool,
                                         refcon: UnsafeMutableRawPointer) {
        guard let matching = IOServiceMatching(className) else { return }
        var iterator: io_iterator_t = 0
        let result: kern_return_t
        if terminated {
            result = IOServiceAddMatchingNotification(
                port, kIOTerminatedNotification, matching,
                { refcon, iterator in LiveMonitor.matchingCallback(refcon, iterator, terminated: true) },
                refcon, &iterator
            )
        } else {
            result = IOServiceAddMatchingNotification(
                port, kIOFirstMatchNotification, matching,
                { refcon, iterator in LiveMonitor.matchingCallback(refcon, iterator, terminated: false) },
                refcon, &iterator
            )
        }
        guard let handle = IOObjectHandle(adopting: iterator), result == KERN_SUCCESS,
              let registrations = notifications else { return }
        registrations.matchIterators.append(handle)
        // Draining the iterator arms the notification.
        serviceEvent(iterator, terminated: terminated)
    }

    private func addInterest(_ entry: RegistryEntry) {
        guard let registrations = notifications, let port = registrations.port, let id = entry.entryID,
              registrations.interest[id] == nil else { return }
        var notification: io_object_t = 0
        let result = IOServiceAddInterestNotification(
            port, entry.raw, kIOGeneralInterest,
            { refcon, _, _, _ in LiveMonitor.interestCallback(refcon) },
            Unmanaged.passUnretained(registrations.box).toOpaque(), &notification
        )
        guard let handle = IOObjectHandle(adopting: notification), result == KERN_SUCCESS else { return }
        registrations.interest[id] = handle
    }

    private func wantsInterest(_ entry: RegistryEntry) -> Bool {
        Self.interestClasses.contains { entry.conforms(to: $0) }
    }

    private func registerPowerSourceNotification() {
        #if canImport(notify)
        var token: Int32 = 0
        let status = notify_register_dispatch(Self.powerSourceNotification, &token, queue) { [weak self] _ in
            self?.externalChangeOnQueue()
        }
        if status == 0 {
            notifications?.powerToken = token
        }
        #endif
    }

    /// Display reconfiguration (and, without `notify`, power-source run loop)
    /// callbacks are registered and removed on the main thread.
    private func registerMainThreadCallbacks() {
        let box = CallbackBox(monitor: self)
        mainThreadBox = box
        Self.onMain {
            let pointer = Unmanaged.passUnretained(box).toOpaque()
            _ = CGDisplayRegisterReconfigurationCallback(LiveMonitor.displayCallback, pointer)
            #if !canImport(notify)
            if let source = IOPSNotificationCreateRunLoopSource(LiveMonitor.powerSourceCallback, pointer)?
                .takeRetainedValue() {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
                box.powerRunLoopSource = source
            }
            #endif
        }
    }

    // MARK: Teardown (on queue)

    private func teardown() {
        guard isRunning else { return }
        isRunning = false
        handler = nil
        pendingCapture?.cancel()
        pendingCapture = nil
        scheduler = CaptureScheduler()
        pollTimer?.cancel()
        pollTimer = nil
        pollInterval = nil

        // This runs on `queue`, the queue the port and the power-source
        // notification deliver on, so no callback is running and none runs
        // after the release.
        notifications?.release()
        notifications = nil

        if let box = mainThreadBox {
            mainThreadBox = nil
            Self.onMain {
                let pointer = Unmanaged.passUnretained(box).toOpaque()
                _ = CGDisplayRemoveReconfigurationCallback(LiveMonitor.displayCallback, pointer)
                if let source = box.powerRunLoopSource {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                    box.powerRunLoopSource = nil
                }
            }
        }
    }

    // MARK: Events (on queue)

    /// Drains a matching iterator: registers interest on new port services,
    /// drops interest for terminated ones, and schedules a capture.
    private func serviceEvent(_ iterator: io_iterator_t, terminated: Bool) {
        var sawService = false
        var count = 0
        while count < RegistryEntry.maxIteratorItems, let entry = RegistryEntry(adopting: IOIteratorNext(iterator)) {
            count += 1
            sawService = true
            guard isRunning else { continue }
            if terminated {
                if let id = entry.entryID {
                    notifications?.interest.removeValue(forKey: id)
                }
            } else if wantsInterest(entry) {
                addInterest(entry)
            }
        }
        if sawService && !isArming {
            scheduleCapture(urgent: false)
        }
    }

    private func externalChangeOnQueue() {
        scheduleCapture(urgent: false)
    }

    private func pollTick() {
        scheduleCapture(urgent: true)
    }

    /// Schedules a capture as `CaptureScheduler` decides: urgent requests run
    /// as soon as the queue is free, other requests are debounced, and a
    /// request that needs new work replaces the queued capture.
    private func scheduleCapture(urgent: Bool) {
        guard isRunning,
              let deadline = scheduler.request(urgent: urgent, now: .now(), debounce: configuration.debounce)
        else { return }
        pendingCapture?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runCapture() }
        pendingCapture = work
        queue.asyncAfter(deadline: deadline, execute: work)
    }

    private func runCapture() {
        pendingCapture = nil
        scheduler.captureStarted()
        guard isRunning, let handler else { return }
        let raw = RegistryCapture.capture(includeSMC: configuration.includeSMC, smc: smc)
        captureCount += 1
        let generation = self.generation
        let gate = self.gate
        DispatchQueue.main.async {
            guard gate.isCurrent(generation) else { return }
            MainActor.assumeIsolated {
                handler(raw)
            }
        }
    }

    private func updatePollTimer() {
        guard isRunning else { return }
        let interval = Self.pollInterval(visible: uiVisible, configuration: configuration)
        let leeway = DispatchTimeInterval.milliseconds(max(10, Int(interval * 100)))
        if let timer = pollTimer {
            guard pollInterval != interval else { return }
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
        } else {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.setEventHandler { [weak self] in self?.pollTick() }
            timer.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
            timer.resume()
            pollTimer = timer
        }
        pollInterval = interval
    }

    // MARK: Helpers

    private func performSync<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return body()
        }
        return queue.sync(execute: body)
    }

    private static func onMain(_ body: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }

    /// Hands a change seen on another thread to the queue, where it is
    /// debounced like an IOKit notification. Tests call it to simulate a
    /// burst of notifications.
    func externalChangeFromAnyThread() {
        queue.async { [weak self] in self?.externalChangeOnQueue() }
    }

    // MARK: C callbacks

    private static func matchingCallback(_ refcon: UnsafeMutableRawPointer?, _ iterator: io_iterator_t,
                                         terminated: Bool) {
        guard let refcon, let monitor = Unmanaged<CallbackBox>.fromOpaque(refcon).takeUnretainedValue().monitor else {
            // No monitor any more: still release the services so the
            // iterator stays balanced.
            var count = 0
            while count < RegistryEntry.maxIteratorItems, RegistryEntry(adopting: IOIteratorNext(iterator)) != nil {
                count += 1
            }
            return
        }
        monitor.serviceEvent(iterator, terminated: terminated)
    }

    private static func interestCallback(_ refcon: UnsafeMutableRawPointer?) {
        guard let refcon else { return }
        Unmanaged<CallbackBox>.fromOpaque(refcon).takeUnretainedValue().monitor?.externalChangeOnQueue()
    }

    /// Registered with CoreGraphics. Ignores the "about to reconfigure" pass.
    private nonisolated(unsafe) static let displayCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
        Unmanaged<CallbackBox>.fromOpaque(userInfo).takeUnretainedValue().monitor?.externalChangeFromAnyThread()
    }

    #if !canImport(notify)
    /// Registered with `IOPSNotificationCreateRunLoopSource` on the main run loop.
    private nonisolated(unsafe) static let powerSourceCallback: IOPowerSourceCallbackType = { context in
        guard let context else { return }
        Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue().monitor?.externalChangeFromAnyThread()
    }
    #endif
}

/// The IOKit notification port and everything registered on it, plus the
/// power-source `notify` token. Only touched on the monitor's queue.
private final class NotificationRegistrations: @unchecked Sendable {
    /// Context passed to the IOKit callbacks; outlives every registration.
    let box: CallbackBox
    var port: IONotificationPortRef?
    var matchIterators: [IOObjectHandle] = []
    var interest: [UInt64: IOObjectHandle] = [:]
    var powerToken: Int32?

    init(box: CallbackBox) {
        self.box = box
    }

    /// Cancels the power-source notification, releases the notification
    /// objects and iterators (which disarms them) and destroys the port last.
    /// Safe to call more than once.
    func release() {
        #if canImport(notify)
        if let powerToken {
            _ = notify_cancel(powerToken)
        }
        #endif
        powerToken = nil
        interest.removeAll()
        matchIterators.removeAll()
        if let port {
            IONotificationPortDestroy(port)
        }
        port = nil
    }
}

/// The context pointer handed to C callbacks. It holds the monitor weakly, so
/// a callback that races with deallocation finds nil instead of a dangling
/// pointer.
private final class CallbackBox: @unchecked Sendable {
    weak var monitor: LiveMonitor?
    /// Main thread only.
    var powerRunLoopSource: CFRunLoopSource?

    init(monitor: LiveMonitor) {
        self.monitor = monitor
    }
}

/// Decides whether a snapshot may still be delivered. `start()` and `stop()`
/// advance the generation, so deliveries queued for the main actor by an
/// earlier run are dropped.
private final class DeliveryGate: Sendable {
    private let state = OSAllocatedUnfairLock<UInt64>(initialState: 0)

    @discardableResult
    func advance() -> UInt64 {
        state.withLock { value in
            value &+= 1
            return value
        }
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        state.withLock { $0 == generation }
    }
}
