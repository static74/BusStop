import CoreGraphics
import Testing
@testable import BusStopApp

@Suite("Map camera")
struct GraphCameraTests {
    let camera = GraphCamera(scale: 0.5, offset: CGPoint(x: 40, y: -20))

    @Test func screenAndLayoutPointsRoundTrip() {
        let point = CGPoint(x: 123, y: 456)
        #expect(camera.layoutPoint(camera.screenPoint(point)) == point)
        #expect(camera.screenPoint(point).applying(.identity) == point.applying(camera.transform))
    }

    @Test func zoomKeepsThePointUnderThePointer() {
        let pointer = CGPoint(x: 300, y: 200)
        let under = camera.layoutPoint(pointer)
        let zoomed = camera.zoomed(to: 1.75, at: pointer)
        #expect(zoomed.scale == 1.75)
        let after = zoomed.screenPoint(under)
        #expect(abs(after.x - pointer.x) < 0.001 && abs(after.y - pointer.y) < 0.001)
    }

    @Test func centeringPutsTheRectInTheMiddle() {
        let size = CGSize(width: 800, height: 600)
        let rect = CGRect(x: 1000, y: 700, width: 100, height: 40)
        #expect(camera.centering(rect, in: size).screenPoint(CGPoint(x: rect.midX, y: rect.midY)) == CGPoint(x: 400, y: 300))
    }

    @Test func clampKeepsPartOfTheGraphOnScreen() {
        let layout = CGSize(width: 2000, height: 1000)
        let size = CGSize(width: 800, height: 600)
        let away = GraphCamera(scale: 1, offset: CGPoint(x: -5000, y: 5000)).clamped(layout: layout, viewport: size)
        #expect(away.offset == CGPoint(x: GraphCamera.keepVisible - 2000, y: 600 - GraphCamera.keepVisible))
        let inside = GraphCamera(scale: 1, offset: CGPoint(x: -100, y: 50))
        #expect(inside.clamped(layout: layout, viewport: size) == inside)
    }

    @Test func fitCentresASmallGraphAndPinsALargeOne() {
        let size = CGSize(width: 800, height: 600)
        #expect(GraphCamera.fit(layout: CGSize(width: 400, height: 200), viewport: size, scale: 1).offset == CGPoint(x: 200, y: 200))
        #expect(GraphCamera.fit(layout: CGSize(width: 2000, height: 200), viewport: size, scale: 1).offset == CGPoint(x: 0, y: 200))
    }
}
