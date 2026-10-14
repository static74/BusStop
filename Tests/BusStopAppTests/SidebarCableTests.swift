import BusStopCore
import Testing
@testable import BusStopApp

@Suite("Sidebar cables")
struct SidebarCableTests {
    @Test func everyLinkIsListedInTreeOrder() {
        func node(_ id: String, _ children: [DeviceNode] = []) -> DeviceNode {
            DeviceNode(id: id, bus: .usb, kind: .hub, name: id.uppercased(), children: children)
        }
        let devices = [node("dock", [node("hub", [node("ipad")]), node("monitor")]), node("drive")]
        let cables = SidebarCable.cables(below: devices, from: "Left Center")
        #expect(cables.map { "\($0.parentName) → \($0.childName)" } == [
            "Left Center → DOCK", "DOCK → HUB", "HUB → IPAD", "DOCK → MONITOR", "Left Center → DRIVE",
        ])
    }
}
