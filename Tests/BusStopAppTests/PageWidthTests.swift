import AppKit
import BusStopCore
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

    /// The Mac Outline's header, outline, captions and "Not placed" list wrap
    /// or shrink; the Data/Power controls are laid over it and set no width.
    @Test(arguments: TextSizeSetting.allCases)
    func silhouettePageFitsANarrowColumn(_ size: TextSizeSetting) {
        for scenario in [DemoScenario.dockStation, .studioDesk] {
            let suite = "BusStopAppTests.SilhouetteWidth.\(size.rawValue).\(scenario.rawValue)"
            defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
            let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            settings.demoMode = true
            settings.demoScenario = scenario
            let store = PortStore(settings: settings)
            store.start()
            defer { store.stop() }
            let host = NSHostingController(rootView:
                MacSilhouettePage(store: store, searchText: "", onSelect: { _ in }).lagoonTextScale(size))

            #expect(host.sizeThatFits(in: CGSize(width: 0, height: 700)).width <= 120, "\(scenario)")
            for width in [120.0, 250, 338, 438, 478] {
                #expect(host.sizeThatFits(in: CGSize(width: width, height: 700)).width <= width + 1, "\(scenario)")
            }
        }
    }

    /// In the 338 pt detail column, a finding's title and an event's title get
    /// the whole line at every text size: the severity chip and the times move
    /// under them instead of squeezing "disconnecting" until it breaks
    /// mid-word. 210 and 224 pt are what the card and the timeline row leave
    /// for the text there (padding, icon and spacing taken off).
    @Test(arguments: TextSizeSetting.allCases)
    func longTitlesStackTheirChipAndTimes(_ size: TextSizeSetting) {
        func height(_ view: some View, _ width: CGFloat) -> CGFloat {
            NSHostingController(rootView: view.lagoonTextScale(size))
                .sizeThatFits(in: CGSize(width: width, height: 2_000)).height
        }
        let date = Date(timeIntervalSince1970: 1_791_115_200)
        let diagnostic = Diagnostic(id: "flakyConnection:usb:1", kind: .flakyConnection, severity: .warning,
                                    title: "iPhone keeps disconnecting", detail: "")
        let title = DiagnosticTitle(diagnostic: diagnostic)
        #expect(height(title, 210) == height(title.stacked, 210))

        let event = ConnectionEvent(id: "deviceDisconnected:usb:1:1", date: date, kind: .deviceDisconnected,
                                    title: "iPhone keeps disconnecting", detail: "Left Front · USB-C")
        let text = EventTimelineText(event: event, now: date.addingTimeInterval(60), relativeColor: .gray)
        #expect(height(text, 224) == height(text.stacked, 224))

        // A short title keeps its chip and times beside it.
        let short = DiagnosticTitle(diagnostic: Diagnostic(id: "a", kind: .overcurrent, severity: .warning,
                                                           title: "Hub", detail: ""))
        #expect(height(short, 210) < height(short.stacked, 210))
    }

    /// The Power page's battery card uses `InspectorRow`, so a long value
    /// must wrap rather than set a minimum width.
    @Test func inspectorRowWrapsALongValue() {
        let host = NSHostingController(rootView: InspectorRow(
            label: "Detail",
            value: "3 × 80 Gb/s one way, 1 × 80 Gb/s the other · tunnelled · Apple Studio Display",
            copyable: true))
        #expect(host.sizeThatFits(in: CGSize(width: 120, height: 700)).width <= 121)
    }
}

/// Hosts the whole topology window as `WindowManager` does and lets AppKit
/// lay it out for a second. Before the fix this ended the test process with
/// an update-constraints exception.
@MainActor
@Suite("Topology window layout", .serialized)
struct TopologyWindowLayoutTests {
    /// dockStation is the Mac Outline's two-face desktop layout.
    @Test(arguments: [
        (TopologySidebarItem.events, DemoScenario.studioDesk), (.diagnostics, .studioDesk),
        (.power, .studioDesk), (.silhouette, .studioDesk), (.silhouette, .dockStation),
    ], [900.0, 1000.0])
    func narrowWindowWithInspectorSettles(page: (item: TopologySidebarItem, scenario: DemoScenario), width: Double) {
        let suite = "BusStopAppTests.WindowLayout"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        settings.demoMode = true
        settings.demoScenario = page.scenario
        let store = PortStore(settings: settings)
        store.start()
        defer { store.stop() }
        // Diagnostics only crashed with a finding to show.
        if page.item == .diagnostics { #expect(!store.snapshot.diagnostics.isEmpty) }

        let host = NSHostingController(rootView: TopologyWindowView(store: store, page: page.item, showsInspector: true))
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
