import AppKit
import SwiftUI

/// Turns mouse scroll-wheel turns over the graph into zoom steps, like a
/// map: wheel away from you zooms in, towards you zooms out, about 10 % a
/// notch. Add it as a background of the graph's scroll view; it draws nothing
/// and never takes clicks.
///
/// Only a mouse wheel zooms: an event that is not part of a gesture (no
/// scroll or momentum phase) and has no modifier keys. Wheels that report
/// smooth, pixel-based deltas count too. A trackpad's or Magic Mouse's
/// two-finger scroll still pans, a pinch still zooms, and Shift with a wheel
/// still scrolls sideways.
struct GraphScrollWheelZoom: NSViewRepresentable {
    /// Called with a zoom factor (above 1 zooms in) and the pointer location
    /// in this view, measured from its top-left corner.
    var onZoom: (Double, CGPoint) -> Void

    func makeNSView(context: Context) -> GraphScrollWheelView {
        let view = GraphScrollWheelView()
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ view: GraphScrollWheelView, context: Context) {
        view.onZoom = onZoom
    }

    static func dismantleNSView(_ view: GraphScrollWheelView, coordinator: Coordinator) {
        view.stopMonitoring()
    }
}

/// The AppKit side of `GraphScrollWheelZoom`: watches the app's scroll-wheel
/// events while it is in a window, and consumes the ones it turns into zoom.
final class GraphScrollWheelView: NSView {
    var onZoom: ((Double, CGPoint) -> Void)?
    private var monitor: Any?

    /// Zoom per line of wheel travel; one notch is usually one line.
    static let stepFactor = 1.1
    /// Fast spins report many lines at once; cap one event at this many.
    static let maxLinesPerEvent: CGFloat = 4

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let wheel = GraphWheelEvent(event)
            let handled = MainActor.assumeIsolated { self?.handle(wheel) ?? false }
            return handled ? nil : event
        }
    }

    /// Zooms for `wheel` when it is a plain mouse-wheel turn over this view.
    /// Returns true when the event was used and must not scroll anything.
    private func handle(_ wheel: GraphWheelEvent) -> Bool {
        guard let onZoom, !wheel.isGesture, !wheel.hasModifiers, wheel.lines != 0,
              let window, window.windowNumber == wheel.windowNumber, window.attachedSheet == nil,
              !isHiddenOrHasHiddenAncestor else { return false }
        let location = convert(wheel.locationInWindow, from: nil)
        guard bounds.contains(location) else { return false }
        let lines = min(max(wheel.lines, -Self.maxLinesPerEvent), Self.maxLinesPerEvent)
        onZoom(pow(Self.stepFactor, Double(lines)), location)
        return true
    }
}

/// The parts of a scroll-wheel event the graph needs, copied out of the
/// `NSEvent` so they can cross into main-actor code.
nonisolated struct GraphWheelEvent: Sendable {
    /// Lines of vertical travel; positive when the wheel turns away from
    /// the user, whatever the natural-scrolling setting. Pixel-based deltas
    /// count about ten points as a line.
    var lines: CGFloat
    /// Part of a trackpad or Magic Mouse gesture (a scroll or momentum
    /// phase is set); a mouse wheel has neither.
    var isGesture: Bool
    var hasModifiers: Bool
    var locationInWindow: CGPoint
    var windowNumber: Int

    init(_ event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 10 : event.scrollingDeltaY
        lines = event.isDirectionInvertedFromDevice ? -delta : delta
        isGesture = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        hasModifiers = !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        locationInWindow = event.locationInWindow
        windowNumber = event.windowNumber
    }
}
