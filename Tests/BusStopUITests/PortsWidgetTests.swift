import AppKit
import BusStopCore
import SwiftUI
import Testing
import WidgetKit
@testable import BusStopUI

@Suite("Ports widget")
@MainActor
struct PortsWidgetTests {
    typealias S = WidgetTestSupport
    typealias Metrics = PortsWidgetLayout.Metrics

    /// The height the rows get on a real widget: the family's, less the
    /// 16-point content margins and the chrome's title row and its spacing.
    static func contentHeight(_ family: S.Family) -> CGFloat { family.size.height - 32 - 30 }

    static func widgetFamily(_ family: S.Family) -> WidgetFamily {
        family == .large ? .systemLarge : .systemExtraLarge
    }

    static func layout(_ ports: [PhysicalPort], _ family: S.Family, height: CGFloat? = nil) -> PortsWidgetLayout {
        PortsWidgetLayout(ports: ports, showsTrees: family == .extraLarge, columnCount: family == .large ? 1 : 2,
                          height: height ?? contentHeight(family))
    }

    /// `count` copies of `port`, numbered so each has its own key.
    static func ports(_ count: Int, like port: PhysicalPort) -> [PhysicalPort] {
        (1...count).map { number in
            var copy = port
            copy.key = PortKey(type: port.key.type, number: number)
            copy.number = number
            return copy
        }
    }

    // MARK: Layout

    @Test(arguments: DemoScenario.allCases, S.Family.allCases)
    func demoScenariosFitWithoutHidingAnything(_ scenario: DemoScenario, _ family: S.Family) {
        let snapshot = S.snapshot(scenario)
        let layout = Self.layout(snapshot.ports, family)
        #expect(layout.columns.flatMap { $0 }.map(\.port.key) == snapshot.ports.map(\.key), "physical order")
        #expect(layout.hiddenPorts == 0)
        #expect(layout.columns.flatMap { $0 }.allSatisfy { $0.hiddenDevices == 0 })
        #expect(layout.gap == Metrics.gap)
        if family == .extraLarge {
            let devices = snapshot.ports.reduce(0) { $0 + $1.deviceCount }
            let rootsInRows = snapshot.ports.filter { $0.devices.count == 1 }.count
            #expect(layout.columns.flatMap { $0 }.reduce(0) { $0 + $1.tree.count } == devices - rootsInRows)
        }
    }

    @Test func treesHangOffTheDeviceInTheRow() throws {
        let port = try #require(S.snapshot(.studioDesk).ports.first { $0.label.shortTitle == "Left Center" })
        let tree = PortsWidgetLayout.tree(of: port)
        // The display's hub is built in, so the drive and the camera hang off the display.
        #expect(tree.map(\.device.name) == ["PSSD T9", "Studio Display XDR Camera"])
        #expect(tree.map(\.depth) == [1, 1])
    }

    @Test func extraLargeBalancesColumnsInOrder() {
        let ports = S.snapshot(.dockStation).ports
        let layout = Self.layout(ports, .extraLarge)
        #expect(layout.columns.count == 2)
        #expect(!layout.columns[0].isEmpty && !layout.columns[1].isEmpty)
        // The dock and its five devices sit in the first column with the two front ports.
        #expect(layout.columns[0].map(\.port.label.shortTitle) == ["Front (left)", "Front (right)", "Rear (left)"])
    }

    @Test func gapsShrinkBeforeAnythingIsHidden() throws {
        let port = try #require(S.snapshot(.unplugged).ports.first)
        // Nine rows need 9 × 32 + 8 × 8 = 352 points at the full gap, and 304 at the smallest.
        let layout = Self.layout(Self.ports(9, like: port), .large, height: 320)
        #expect(layout.hiddenPorts == 0)
        #expect(layout.gap < Metrics.gap && layout.gap >= Metrics.minimumGap)
        #expect(PortsWidgetLayout.height(layout.columns[0], gap: layout.gap) <= 320)
    }

    @Test func portsThatDoNotFitBecomeAMoreLine() throws {
        let port = try #require(S.snapshot(.unplugged).ports.first)
        let ports = Self.ports(14, like: port)
        let layout = Self.layout(ports, .large)
        let shown = layout.columns[0]
        #expect(layout.hiddenPorts > 0)
        #expect(shown.count + layout.hiddenPorts == 14)
        #expect(shown.map(\.port.key) == Array(ports.prefix(shown.count)).map(\.key), "the first ports stay")
        #expect(PortsWidgetLayout.height(shown, gap: layout.gap, reservesMoreLine: true) <= Self.contentHeight(.large))
    }

    @Test func longTreesLoseTheirLastDevicesFirst() throws {
        let dock = try #require(S.snapshot(.dockStation).ports.first { !PortsWidgetLayout.tree(of: $0).isEmpty })
        let ports = Self.ports(4, like: dock)
        let height: CGFloat = 200
        let layout = Self.layout(ports, .extraLarge, height: height)
        #expect(layout.hiddenPorts == 0)
        for column in layout.columns {
            #expect(PortsWidgetLayout.height(column, gap: layout.gap) <= height)
            for block in column {
                #expect(block.tree.count + block.hiddenDevices == 5)
                #expect(block.tree.map(\.device.id) == PortsWidgetLayout.tree(of: dock).prefix(block.tree.count).map(\.device.id))
            }
        }
        #expect(layout.columns.flatMap { $0 }.contains { $0.hiddenDevices > 0 })
    }

    // MARK: Rendering

    @Test(arguments: DemoScenario.allCases, S.Family.allCases)
    func drawsEveryScenario(_ scenario: DemoScenario, _ family: S.Family) throws {
        let entry = S.entry(scenario)
        for mode in [WidgetRenderingMode.fullColor, .vibrant, .accented] {
            for scheme in [ColorScheme.dark, .light] {
                let view = PortsWidgetView(entry: entry, family: Self.widgetFamily(family))
                    .environment(\.widgetRenderingMode, mode)
                #expect(S.hasContent(try S.render(view, family, colorScheme: scheme)), "\(mode) \(scheme)")
            }
        }
    }

    /// The rows' ideal height, measured, stays within the height the layout was given.
    @Test(arguments: DemoScenario.allCases, S.Family.allCases)
    func nothingIsClipped(_ scenario: DemoScenario, _ family: S.Family) throws {
        let snapshot = S.snapshot(scenario)
        let height = Self.contentHeight(family)
        let content = PortsWidgetContent(snapshot: snapshot, layout: Self.layout(snapshot.ports, family))
            .frame(width: family.size.width - 32)
            .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(CGFloat(image.height) <= height)
    }

    @Test func overflowingPortsStillFitWhenRendered() throws {
        let port = try #require(S.snapshot(.studioDesk).ports.first { $0.devices.count == 1 })
        var snapshot = S.snapshot(.studioDesk)
        snapshot.ports = Self.ports(12, like: port)
        for family in S.Family.allCases {
            let layout = Self.layout(snapshot.ports, family)
            let content = PortsWidgetContent(snapshot: snapshot, layout: layout)
                .frame(width: family.size.width - 32)
                .fixedSize(horizontal: false, vertical: true)
            let renderer = ImageRenderer(content: content)
            let image = try #require(renderer.cgImage)
            #expect(CGFloat(image.height) / renderer.scale <= Self.contentHeight(family), "\(family)")
        }
    }

    // MARK: Review images

    /// Writes PNGs of every scenario, family and appearance, plus a vibrant
    /// approximation, to `WIDGET_REVIEW_DIR` when it is set, for looking at.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WIDGET_REVIEW_DIR"] != nil))
    func writeReviewImages() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["WIDGET_REVIEW_DIR"]!)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var crowded = S.snapshot(.studioDesk)
        crowded.ports = Self.ports(12, like: crowded.ports[1])
        let cases = DemoScenario.allCases.map { ($0.rawValue, S.entry($0)) }
            + [("stale", S.entry(.studioDesk, state: .stale)),
               ("overflow", WidgetTimeline.Entry(date: S.date, state: .live, payload: WidgetPayload(snapshot: crowded)))]
        for (name, entry) in cases {
            for family in S.Family.allCases {
                for scheme in [ColorScheme.dark, .light] {
                    let view = PortsWidgetView(entry: entry, family: Self.widgetFamily(family))
                    let png = try Self.reviewPNG(view, family, scheme: scheme, vibrant: false)
                    try png.write(to: directory.appending(path: "\(name)-\(family.rawValue)-\(scheme).png"))
                }
                let view = PortsWidgetView(entry: entry, family: Self.widgetFamily(family))
                    .environment(\.widgetRenderingMode, .vibrant)
                let png = try Self.reviewPNG(view, family, scheme: .dark, vibrant: true)
                try png.write(to: directory.appending(path: "\(name)-\(family.rawValue)-vibrant.png"))
            }
        }
    }

    /// At 2×, inside 16-point margins on the widget background (which tests
    /// do not draw). Vibrant keeps only each pixel's brightness, as white
    /// over a grey desktop, roughly as macOS draws a covered widget.
    static func reviewPNG(_ view: some View, _ family: S.Family, scheme: ColorScheme, vibrant: Bool) throws -> Data {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let framed = view
            .padding(16)
            .frame(width: family.size.width, height: family.size.height)
            .background { if !vibrant { shape.fill(Lagoon.background) } }
            .clipShape(shape)
            .padding(12)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        var image = try #require(renderer.cgImage)
        if vibrant {
            // Premultiplied RGBA, so each channel already carries its alpha.
            let context = try #require(CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = context.data!.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
            for i in stride(from: 0, to: image.width * image.height * 4, by: 4) {
                let ink = (0.3 * Double(pixels[i]) + 0.59 * Double(pixels[i + 1]) + 0.11 * Double(pixels[i + 2])) / 255
                let grey = UInt8((0.32 + 0.68 * ink) * 255)
                (pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]) = (grey, grey, grey, 255)
            }
            image = try #require(context.makeImage())
        }
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
