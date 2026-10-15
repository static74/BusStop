import AppKit
import SwiftUI
import Testing
@testable import BusStopApp

/// The map's picker and zoom cluster sit in their own hosting views so their
/// tooltips do not depend on the map's (see `GraphControlHost` and
/// docs/decisions.md). These check that they still behave as they did
/// inside the map's hosting view.
@MainActor
@Suite("Map control hosts", .serialized)
struct GraphControlHostTests {
    /// Hosts `root` in a borderless window and lets it lay out.
    private func host<Root: View>(_ root: Root, size: CGSize) -> (NSWindow, NSHostingView<Root>) {
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
        }
        return (window, host)
    }

    private func hostedControls(in view: NSView) -> [GraphControlHostingView] {
        view.subviews.flatMap { subview -> [GraphControlHostingView] in
            if let hosted = subview as? GraphControlHostingView { return [hosted] }
            return hostedControls(in: subview)
        }
    }

    @Test func pickerAndZoomClusterHaveTheirOwnHostingViews() {
        let suite = "BusStopAppTests.GraphControlHost"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.demoMode = true
        settings.demoScenario = .studioDesk
        let store = PortStore(settings: settings)
        store.start()
        defer { store.stop() }

        let size = CGSize(width: 1000, height: 700)
        let (window, map) = host(
            TopologyGraphView(store: store, ports: store.snapshot.ports, includeOther: true, searchText: "",
                              camera: .constant(nil), isWindowVisible: false, scrollRequest: .constant(nil)),
            size: size
        )
        defer { window.close() }

        let controls = hostedControls(in: map).sorted { $0.frame.minX < $1.frame.minX }
        #expect(controls.count == 2)
        guard controls.count == 2 else { return }
        // Picker bottom left, zoom cluster bottom right, each the size of
        // its content rather than the width of the map.
        for control in controls {
            let frame = control.convert(control.bounds, to: map)
            #expect(frame.width > 40 && frame.width < 300, "\(frame)")
            #expect(frame.maxY > size.height - 60, "\(frame)")
        }
        #expect(controls[0].convert(controls[0].bounds, to: map).minX < 100)
        #expect(controls[1].convert(controls[1].bounds, to: map).maxX > size.width - 100)
    }

    @Test func zoomShortcutsReachTheHostedCluster() throws {
        let box = ZoomBox()
        let (window, _) = host(
            GraphControlHost {
                GraphZoomControl(zoom: 1, isFitting: false, onZoom: { box.zooms.append($0) }, onFit: { box.fits += 1 })
            }
            .fixedSize(),
            size: CGSize(width: 300, height: 60)
        )
        defer { window.close() }

        for (key, code) in [("=", UInt16(24)), ("-", 27), ("0", 29), ("9", 25)] {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: key,
                charactersIgnoringModifiers: key, isARepeat: false, keyCode: code
            ))
            #expect(window.performKeyEquivalent(with: event), "⌘\(key)")
        }
        #expect(box.zooms == [1.1, 0.9, 1])
        #expect(box.fits == 1)
    }

    @Test func hostedContentFollowsTheTextSize() {
        func width(_ size: TextSizeSetting) -> CGFloat {
            let (window, hostView) = host(
                GraphControlHost { Text("Zoom to Fit").lagoonFont(.caption) }
                    .fixedSize()
                    .lagoonTextScale(size),
                size: CGSize(width: 400, height: 100)
            )
            defer { window.close() }
            return hostedControls(in: hostView).first?.fittingSize.width ?? 0
        }
        #expect(width(.extraLarge) > width(.small) * 1.2)
    }
}

@MainActor private final class ZoomBox {
    var zooms: [Double] = []
    var fits = 0
}
