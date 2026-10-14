import AppKit
import SwiftUI
import Testing
@testable import BusStopApp

/// A page that is wider than the detail column used to crash the topology
/// window with the inspector open (issue #5). See `docs/decisions.md`.
@MainActor
@Suite("Page minimum widths")
struct PageWidthTests {
    @Test(arguments: TextSizeSetting.allCases)
    func eventsPageFitsANarrowColumn(_ size: TextSizeSetting) {
        let suite = "BusStopAppTests.PageWidth.\(size.rawValue)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = PortStore(settings: AppSettings(defaults: UserDefaults(suiteName: suite)!))
        let host = NSHostingController(rootView:
            EventsDetailView(store: store, searchText: "", onSelect: { _ in }).lagoonTextScale(size))

        // Only the empty state's text sets a floor; the filter and Clear move
        // under the title instead.
        #expect(host.sizeThatFits(in: CGSize(width: 0, height: 700)).width <= 120)
        // 338 and 438 pt are the detail column at 900 and 1000 pt with the
        // default sidebar (232) and inspector (330); 478 is the column at 1040.
        for width in [120.0, 250, 338, 438, 478] {
            #expect(host.sizeThatFits(in: CGSize(width: width, height: 700)).width <= width + 1)
        }
    }
}

/// Hosts the whole topology window as `WindowManager` does and lets AppKit
/// lay it out for a second. Before the fix this ended the test process with
/// an update-constraints exception.
@MainActor
@Suite("Topology window layout", .serialized)
struct TopologyWindowLayoutTests {
    @Test(arguments: [TopologySidebarItem.events, .diagnostics], [900.0, 1000.0])
    func narrowWindowWithInspectorSettles(page: TopologySidebarItem, width: Double) {
        let suite = "BusStopAppTests.WindowLayout"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.demoMode = true
        settings.demoScenario = .studioDesk
        let store = PortStore(settings: settings)
        store.start()
        defer { store.stop() }
        // Diagnostics only crashed with a finding to show.
        #expect(!store.snapshot.diagnostics.isEmpty)

        let host = NSHostingController(rootView: TopologyWindowView(store: store, page: page, showsInspector: true))
        host.sceneBridgingOptions = [.toolbars, .title]
        host.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentViewController = host
        window.toolbarStyle = .unified
        window.contentMinSize = WindowManager.minimumTopologySize
        window.setContentSize(NSSize(width: width, height: 700))

        for _ in 0..<20 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            window.displayIfNeeded()
        }
        // Still the width it was given: nothing forced the window wider.
        #expect(abs(host.view.frame.width - width) < 0.5)
    }
}
