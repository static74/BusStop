import BusStopCore
import Foundation
import Testing
@testable import BusStopCLI

@MainActor
@Suite("Watch session")
struct WatchSessionTests {
    private let start = Date(timeIntervalSince1970: 1_791_115_200)

    /// A Studio desk capture `seconds` after `start`, with a drive named after `serial` or without it.
    private func drive(_ serial: String, at seconds: TimeInterval, plugged: Bool) throws -> RawSnapshot {
        var raw = DemoScenario.studioDesk.raw(at: start + seconds, tick: 0)
        let index = try #require(raw.usbDevices.firstIndex { $0.node.properties.values["USB Serial Number"] != nil })
        var values = raw.usbDevices[index].node.properties.values
        values["USB Serial Number"] = .string(serial)
        values["USB Product Name"] = .string("Drive \(serial)")
        raw.usbDevices[index].node.properties = PropertyBag(values)
        raw.usbDevices[index].node.name = "Drive \(serial)"
        if !plugged { raw.usbDevices.remove(at: index) }
        return raw
    }

    /// The drive keeps disconnecting, then stays away: no line names it by its serial,
    /// the "keeps disconnecting" one included.
    @Test func goneDeviceSerialStaysOutOfTheLines() throws {
        let serial = "SNXYZ123"
        let session = WatchSession(options: CLIOptions())
        var seconds: TimeInterval = 0
        var lines = session.events(after: try drive(serial, at: seconds, plugged: true), isDemo: false)
        for _ in 0..<5 {
            seconds += 5
            lines += session.events(after: try drive(serial, at: seconds, plugged: false), isDemo: false)
            seconds += 5
            lines += session.events(after: try drive(serial, at: seconds, plugged: true), isDemo: false)
        }
        for _ in 0..<7 {
            seconds += 5
            lines += session.events(after: try drive(serial, at: seconds, plugged: false), isDemo: false)
        }
        #expect(lines.contains { $0.kind == .diagnosticRaised })
        for event in lines {
            #expect(!event.title.contains(serial) && !event.detail.contains(serial), "\(event.title)")
        }
    }
}
