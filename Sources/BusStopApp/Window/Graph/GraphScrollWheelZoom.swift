import AppKit
import SwiftUI

/// Turns scroll-wheel events over the map into zoom and pan, like a web
/// map. Add it as a background of the map; it draws nothing and never takes
/// clicks.
///
/// A mouse wheel zooms: wheel away from you zooms in, towards you zooms out,
/// about 10 % a notch. That is an event that is not part of a gesture (no
/// scroll or momentum phase) and has no modifier keys; wheels that report
/// smooth, pixel-based deltas count too. Everything else pans: a trackpad's
/// or Magic Mouse's two-finger scroll (with its momentum), and a wheel with
/// a modifier, such as Shift to move sideways.
///
/// It also reports mouse buttons pressed over the map, without taking them,
/// so the map can hide its tooltip as the system does.
struct GraphScrollWheelZoom: NSViewRepresentable {
    /// Called with a zoom factor (above 1 zooms in) and the pointer location
    /// in this view, measured from its top-left corner.
    var onZoom: (CGFloat, CGPoint) -> Void
    /// Called with how far the map should move, in points.
    var onPan: (CGSize) -> Void
    /// Called when a mouse button goes down over the map.
    var onMouseDown: () -> Void = {}

    func makeNSView(context: Context) -> GraphScrollWheelView {
        let view = GraphScrollWheelView()
        view.onZoom = onZoom
        view.onPan = onPan
        view.onMouseDown = onMouseDown
        return view
    }

    func updateNSView(_ view: GraphScrollWheelView, context: Context) {
        view.onZoom = onZoom
        view.onPan = onPan
        view.onMouseDown = onMouseDown
    }

    static func dismantleNSView(_ view: GraphScrollWheelView, coordinator: Coordinator) {
        view.stopMonitoring()
    }
}

/// The AppKit side of `GraphScrollWheelZoom`: watches the app's scroll-wheel
/// events while it is in a window, and consumes the ones it turns into zoom.
/// Mouse-downs are watched too, and always passed on.
final class GraphScrollWheelView: NSView {
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    var onPan: ((CGSize) -> Void)?
    var onMouseDown: (() -> Void)?
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
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard event.type == .scrollWheel else {
                let location = event.locationInWindow
                let windowNumber = event.windowNumber
                MainActor.assumeIsolated { self?.handleMouseDown(at: location, windowNumber: windowNumber) }
                return event
            }
            let wheel = GraphWheelEvent(event)
            let handled = MainActor.assumeIsolated { self?.handle(wheel) ?? false }
            return handled ? nil : event
        }
    }

    private func handleMouseDown(at locationInWindow: CGPoint, windowNumber: Int) {
        guard let window, window.windowNumber == windowNumber, !isHiddenOrHasHiddenAncestor,
              bounds.contains(convert(locationInWindow, from: nil)) else { return }
        onMouseDown?()
    }

    /// Zooms or pans for `wheel` when it is over this view. Returns true
    /// when the event was used and must not scroll anything else.
    private func handle(_ wheel: GraphWheelEvent) -> Bool {
        guard let window, window.windowNumber == wheel.windowNumber, window.attachedSheet == nil,
              !isHiddenOrHasHiddenAncestor else { return false }
        let location = convert(wheel.locationInWindow, from: nil)
        guard bounds.contains(location) else { return false }
        if !wheel.isGesture, !wheel.hasModifiers {
            guard wheel.lines != 0 else { return true }
            let lines = min(max(wheel.lines, -Self.maxLinesPerEvent), Self.maxLinesPerEvent)
            onZoom?(pow(Self.stepFactor, lines), location)
        } else if wheel.pan != .zero {
            onPan?(wheel.pan)
        }
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
    /// How far the content should move, in points: the scroll deltas, which
    /// already follow the natural-scrolling setting. A line counts as ten
    /// points.
    var pan: CGSize
    var locationInWindow: CGPoint
    var windowNumber: Int

    init(_ event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 10 : event.scrollingDeltaY
        lines = event.isDirectionInvertedFromDevice ? -delta : delta
        isGesture = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        hasModifiers = !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        let points: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        pan = CGSize(width: event.scrollingDeltaX * points, height: event.scrollingDeltaY * points)
        locationInWindow = event.locationInWindow
        windowNumber = event.windowNumber
    }
}
