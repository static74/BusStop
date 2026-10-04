import AppKit
import SwiftUI

/// Reports what happens to the window that hosts this view: whether it is on
/// screen and not covered, when it closes, and when it or the app becomes
/// active again. Add it as a background; it draws nothing.
///
/// The topology window uses it to pause the graph's pulses while nobody can
/// see them, and the settings panes use it to re-read system state after the
/// user comes back from System Settings.
struct HostingWindowObserver: NSViewRepresentable {
    /// Visible means on screen, not minimised and at least partly uncovered.
    var onVisibilityChange: ((Bool) -> Void)? = nil
    /// The window is about to close (Bus Stop keeps closed windows for reuse).
    var onClose: (() -> Void)? = nil
    /// The window became key or the app became active.
    var onActivate: (() -> Void)? = nil

    func makeNSView(context: Context) -> HostingWindowObserverView {
        let view = HostingWindowObserverView()
        view.handlers = self
        return view
    }

    func updateNSView(_ view: HostingWindowObserverView, context: Context) {
        view.handlers = self
    }
}

/// The AppKit side of `HostingWindowObserver`: a zero-size view that watches
/// its window's notifications.
final class HostingWindowObserverView: NSView {
    var handlers = HostingWindowObserver()
    private var tokens: [NSObjectProtocol] = []
    private var lastVisible: Bool?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        stopObserving()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        observe(window)
        // Report after the current SwiftUI update, never in the middle of it.
        Task { @MainActor [weak self] in
            self?.reportVisibility()
        }
    }

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        let visibilityChanges: [Notification.Name] = [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ]
        for name in visibilityChanges {
            tokens.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reportVisibility()
                }
            })
        }
        tokens.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowWillClose()
            }
        })
        tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reportVisibility()
                self?.handlers.onActivate?()
            }
        })
        tokens.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlers.onActivate?()
            }
        })
    }

    private func stopObserving() {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
        tokens.removeAll()
    }

    private func windowWillClose() {
        report(false)
        handlers.onClose?()
    }

    private func reportVisibility() {
        guard let window else { return }
        report(window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible))
    }

    private func report(_ visible: Bool) {
        guard visible != lastVisible else { return }
        lastVisible = visible
        handlers.onVisibilityChange?(visible)
    }
}
