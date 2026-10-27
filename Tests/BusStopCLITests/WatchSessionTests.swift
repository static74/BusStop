import BusStopCore
import Foundation
import Testing
@testable import BusStopCLI

@MainActor
@Suite("Watch session")
struct WatchSessionTests {
    private let start = Date(timeIntervalSince1970: 1_791_115_200)

    /// Studio desk at `seconds`, the Kingston drive named after `serial`, without the named devices.
    private func studioDesk(_ seconds: TimeInterval, serial: String, without names: Set<String>) -> RawSnapshot {
        var raw = DemoScenario.studioDesk.raw(at: start + seconds, tick: 0)
        for index in raw.usbDevices.indices where raw.usbDevices[index].node.name == "DataTraveler 3.0" {
            var values = raw.usbDevices[index].node.properties.values
            values["USB Serial Number"] = .string(serial)
            values["USB Product Name"] = .string("Drive \(serial)")
            values["kUSBProductString"] = .string("Drive \(serial)")
            raw.usbDevices[index].node.properties = PropertyBag(values)
            raw.usbDevices[index].node.name = "Drive \(serial)"
        }
        raw.usbDevices.removeAll { names.contains($0.node.name) }
        return raw
    }

    /// The drive and keyboard behind a hub keep dropping, the drive leaves, then the hub:
    /// the finding's culprit moves to the gone drive, which neither capture holds.
    @Test func findingAboutAGoneDeviceStaysRedacted() {
        let serial = "SNXYZ123"
        let session = WatchSession(options: CLIOptions())
        let drive = "Drive \(serial)"
        var seconds: TimeInterval = 0
        var lines = session.events(after: studioDesk(seconds, serial: serial, without: []), isDemo: false)
        seconds = 20
        lines += session.events(after: studioDesk(seconds, serial: serial, without: []), isDemo: false)
        for _ in 0..<3 {
            seconds += 5
            lines += session.events(after: studioDesk(seconds, serial: serial, without: [drive, "Keychron K8 Pro"]),
                                    isDemo: false)
            seconds += 5
            lines += session.events(after: studioDesk(seconds, serial: serial, without: []), isDemo: false)
        }
        seconds += 5
        lines += session.events(after: studioDesk(seconds, serial: serial, without: [drive]), isDemo: false)
        let hubGone: Set<String> = [drive, "Keychron K8 Pro", "USB Optical Mouse", "USB2.1 Hub", "USB3.1 Hub"]
        seconds += 5
        lines += session.events(after: studioDesk(seconds, serial: serial, without: hubGone), isDemo: false)
        #expect(lines.contains { $0.kind == .diagnosticRaised && $0.title.contains("REDACTED") })
        for event in lines {
            #expect(!event.title.contains(serial) && !event.detail.contains(serial), "\(event.title) · \(event.detail)")
        }
    }
}
