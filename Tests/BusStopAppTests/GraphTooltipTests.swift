import AppKit
import BusStopCore
import SwiftUI
import Testing
@testable import BusStopApp

// Serialized: the hosting-view tests hold the main actor while they lay out,
// which would stretch the timing test's waits.
@Suite("Map tooltips", .serialized)
struct GraphTooltipTests {
    // MARK: Finding the chip

    @Test func theSmallestRegionUnderThePointerWins() {
        let regions = [
            GraphTooltipRegion(id: "big", text: "", rect: CGRect(x: 0, y: 0, width: 200, height: 100)),
            GraphTooltipRegion(id: "chip", text: "", rect: CGRect(x: 10, y: 10, width: 60, height: 16)),
        ]
        #expect(GraphTooltip.region(at: CGPoint(x: 20, y: 20), in: regions)?.id == "chip")
        #expect(GraphTooltip.region(at: CGPoint(x: 150, y: 50), in: regions)?.id == "big")
        #expect(GraphTooltip.region(at: CGPoint(x: 250, y: 50), in: regions) == nil)
        #expect(GraphTooltip.region(at: CGPoint(x: 20, y: 20), in: []) == nil)
    }

    // MARK: Placing the tooltip

    let map = CGSize(width: 800, height: 600)
    let bubble = CGSize(width: 120, height: 22)

    @Test func tooltipIsCentredUnderItsChip() {
        let chip = CGRect(x: 300, y: 200, width: 60, height: 16)
        #expect(GraphTooltip.origin(of: bubble, for: chip, in: map)
                == CGPoint(x: chip.midX - bubble.width / 2, y: chip.maxY + GraphTooltip.gap))
    }

    @Test func tooltipGoesAboveItsChipNearTheControls() {
        let chip = CGRect(x: 300, y: map.height - GraphTooltip.bottomInset - 20, width: 60, height: 16)
        #expect(GraphTooltip.origin(of: bubble, for: chip, in: map).y == chip.minY - GraphTooltip.gap - bubble.height)
    }

    @Test func tooltipStaysInsideTheMap() {
        let left = CGRect(x: -20, y: 100, width: 60, height: 16)
        #expect(GraphTooltip.origin(of: bubble, for: left, in: map).x == GraphTooltip.margin)
        let right = CGRect(x: map.width - 10, y: 100, width: 60, height: 16)
        #expect(GraphTooltip.origin(of: bubble, for: right, in: map).x == map.width - GraphTooltip.margin - bubble.width)
        let top = CGRect(x: 300, y: -40, width: 60, height: 16)
        #expect(GraphTooltip.origin(of: bubble, for: top, in: map).y == GraphTooltip.margin)
    }

    @Test func screenRectFollowsTheCamera() {
        let camera = GraphCamera(scale: 2, offset: CGPoint(x: 40, y: -20))
        let rect = CGRect(x: 100, y: 50, width: 60, height: 16)
        #expect(GraphTooltip.screenRect(rect, camera: camera) == CGRect(x: 240, y: 80, width: 120, height: 32))
    }

    // MARK: Texts

    let tenGigabit = LinkInfo(family: .usb, generation: "USB 3.2 Gen 2", bitsPerSecond: 10_000_000_000)

    @Test @MainActor func chipTextsMatchWhatTheSystemTooltipsSaid() {
        #expect(SpeedChip.helpText(tenGigabit) == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(PowerChip.helpText(GraphEdgePower(milliwatts: 47_000, flowsToParent: true, isMeasured: true))
                == "47 W measured")
        #expect(PowerChip.helpText(GraphEdgePower(milliwatts: 4_500, flowsToParent: false, isMeasured: false))
                == "Up to 4.5 W budgeted for USB devices")
        #expect(TransportChip.helpText(TransportInfo(kind: .usb3, isActive: true, link: tenGigabit))
                == "USB 3.2 Gen 2 @ 10 Gb/s")
        #expect(TransportChip.helpText(TransportInfo(kind: .displayPort, isActive: true)) == "DisplayPort")
        #expect(PowerBadge.helpText(milliwatts: 61_000, direction: .input, isMeasured: true) == "61 W into the Mac")
        #expect(PowerBadge.helpText(milliwatts: 4_500, direction: .output, isMeasured: false)
                == "4.5 W to devices (allocated)")
        #expect(PowerBadge.helpText(milliwatts: 4_500, direction: .input, isMeasured: false)
                == "4.5 W into the Mac (contract)")
    }

    // MARK: Timing

    @Test @MainActor func tooltipShowsAfterTheDelayAndHidesOnDismiss() async throws {
        let state = GraphTooltipState()
        state.initialDelay = .milliseconds(30)
        let chip = GraphTooltipRegion(id: "a/power", text: "4.5 W to devices", rect: CGRect(x: 0, y: 0, width: 50, height: 16))
        state.setRegions([chip])
        state.mapPointerMoved(to: CGPoint(x: 10, y: 8))
        #expect(state.shown == nil)
        await waitUntil { state.shown != nil }
        #expect(state.shown == chip)

        // A click hides it, and it stays hidden while the pointer stays on the chip.
        state.dismiss()
        state.mapPointerMoved(to: CGPoint(x: 12, y: 8))
        try await Task.sleep(for: .milliseconds(150))
        #expect(state.shown == nil)

        // Leaving and coming back shows it again.
        state.mapPointerMoved(to: nil)
        state.mapPointerMoved(to: CGPoint(x: 12, y: 8))
        await waitUntil { state.shown != nil }
        #expect(state.shown == chip)

        // A new reading updates the text; a chip that goes away takes its tooltip.
        let newer = GraphTooltipRegion(id: chip.id, text: "5 W to devices", rect: chip.rect)
        state.setRegions([newer])
        #expect(state.shown == newer)
        state.setRegions([])
        #expect(state.shown == nil)
    }

    let cardChip = GraphTooltipRegion(id: "port:1/power", text: "card", rect: CGRect(x: 0, y: 0, width: 50, height: 16))
    let otherCardChip = GraphTooltipRegion(id: "port:2/power", text: "other card", rect: CGRect(x: 0, y: 100, width: 50, height: 16))
    let linkChip = GraphTooltipRegion(id: "edge:a/speed", text: "link", rect: CGRect(x: 200, y: 0, width: 50, height: 16))

    @Test @MainActor func movingOnFromATooltipShowsTheNextOneQuickly() async {
        let state = GraphTooltipState()
        state.initialDelay = .milliseconds(30)
        state.setRegions([cardChip, linkChip])
        state.mapPointerMoved(to: CGPoint(x: 10, y: 8))
        await waitUntil { state.shown != nil }
        #expect(state.shown?.id == cardChip.id)

        // Too long to wait for: only the switch delay can bring the next one up.
        state.initialDelay = .seconds(30)
        state.mapPointerMoved(to: CGPoint(x: 210, y: 8))
        #expect(state.shown == nil)
        await waitUntil { state.shown != nil }
        #expect(state.shown?.id == linkChip.id)
    }

    @Test @MainActor func pointerFallsBackFromTheCardToTheHitLayer() async {
        let state = GraphTooltipState()
        state.initialDelay = .milliseconds(10)
        state.switchDelay = .milliseconds(10)
        state.setRegions([cardChip, otherCardChip, linkChip])

        state.mapPointerMoved(to: CGPoint(x: 210, y: 8))
        await waitUntil { state.shown?.id == linkChip.id }
        #expect(state.shown?.id == linkChip.id)

        // The card reports last, so it wins.
        state.cardPointerMoved("port:1", to: CGPoint(x: 10, y: 8))
        await waitUntil { state.shown?.id == cardChip.id }
        #expect(state.shown?.id == cardChip.id)

        // Leaving the card goes back to what the hit layer last reported.
        state.cardPointerMoved("port:1", to: nil)
        await waitUntil { state.shown?.id == linkChip.id }
        #expect(state.shown?.id == linkChip.id)

        // A card left after another was entered does not clear the pointer.
        state.cardPointerMoved("port:2", to: CGPoint(x: 10, y: 108))
        state.cardPointerMoved("port:1", to: nil)
        await waitUntil { state.shown?.id == otherCardChip.id }
        #expect(state.shown?.id == otherCardChip.id)
    }

    @Test @MainActor func nothingShowsWhileTheWindowIsInactiveOrAfterTheMapMoves() async throws {
        let state = GraphTooltipState()
        state.initialDelay = .milliseconds(10)
        state.setRegions([cardChip])
        state.setActive(false)
        state.cardPointerMoved("port:1", to: CGPoint(x: 10, y: 8))
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.shown == nil)

        state.setActive(true)
        state.cardPointerMoved("port:1", to: CGPoint(x: 12, y: 8))
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.shown == nil)

        // After the map moves, the old pointer no longer counts.
        state.cameraMoved()
        state.setRegions([cardChip])
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.shown == nil)
    }

    /// Waits up to two seconds for `condition`.
    @MainActor private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Regions in a hosting view

    /// A port card with three transports and a power badge, drawn at 200 %
    /// in a drawing group the way the map draws it.
    @MainActor private func regions(cardWidth: CGFloat) -> [GraphTooltipRegion] {
        let link40 = LinkInfo(family: .thunderbolt, generation: "Thunderbolt / USB4", bitsPerSecond: 40_000_000_000)
        let port = PhysicalPort(
            key: PortKey(type: PortKey.usbCType, number: 1), kind: .usbC, number: 1, registryName: "Port-USB-C@1",
            label: PortLabel(location: "Left Front", source: .catalog, connector: "USB-C", number: 1),
            activeTransports: [
                TransportInfo(kind: .cio, isActive: true, link: link40),
                TransportInfo(kind: .usb3, isActive: true, link: tenGigabit),
                TransportInfo(kind: .displayPort, isActive: true),
            ],
            isConnected: true,
            power: PortPower(direction: .output, milliwatts: 4_500, source: .telemetry)
        )
        let node = GraphNode(id: "port:1", content: .port(port), column: 1,
                             frame: CGRect(x: 300, y: 100, width: cardWidth, height: 84), tag: "port")
        let camera = GraphCamera(scale: 2, offset: CGPoint(x: -500, y: 20))
        let box = RegionBox()
        let root = ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                GraphNodeView(node: node, snapshot: .placeholder(), isSelected: false, isDimmed: false, onSelect: {})
                    .frame(width: node.frame.width, height: node.frame.height)
                    .scaleEffect(camera.scale)
                    .position(camera.screenPoint(CGPoint(x: node.frame.midX, y: node.frame.midY)))
            }
            .frame(width: 1000, height: 600, alignment: .topLeading)
            .drawingGroup()
            .environment(\.showsChipHelp, false)
            .onPreferenceChange(GraphTooltipRegionsKey.self) { box.regions = $0 }
        }
        .frame(width: 1000, height: 600)

        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        return box.regions
    }

    @Test @MainActor func cardChipsPublishLayoutRectsThroughTheDrawingGroup() {
        let regions = regions(cardWidth: 480)
        let frame = CGRect(x: 300, y: 100, width: 480, height: 84)
        #expect(Set(regions.map(\.id)) == ["port:1/power", "port:1/transport:CIO", "port:1/transport:USB3",
                                            "port:1/transport:DisplayPort"])
        // Measured before the zoom: inside the card's layout frame, at chip size.
        for region in regions {
            #expect(frame.contains(region.rect), "\(region.id) at \(region.rect)")
            #expect(region.rect.height < 30, "\(region.id) at \(region.rect)")
        }
        #expect(regions.first { $0.id == "port:1/power" }?.text == "4.5 W to devices")
    }

    @Test @MainActor func trimmedChipsPublishOnlyWhatIsShown() {
        let regions = regions(cardWidth: 200)
        let transports = regions.filter { $0.id.contains("transport:") }
        #expect(!transports.isEmpty && transports.count < 3)
        #expect(Set(regions.map(\.id)).count == regions.count)
    }
}

@MainActor private final class RegionBox {
    var regions: [GraphTooltipRegion] = []
}
