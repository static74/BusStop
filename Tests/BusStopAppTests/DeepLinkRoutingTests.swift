import BusStopCore
import Foundation
import Testing
@testable import BusStopApp

/// Deep links and `BUSSTOP_AUTOMATION` name the same topology pages.
@MainActor
@Suite("Deep link routing")
struct DeepLinkRoutingTests {
    @Test func everyLinkPageIsATopologyPage() {
        let pages = BusStopLink.Page.allCases.map(TopologySidebarItem.init)
        #expect(pages == [.overview, .silhouette, .allPorts, .devices, .power, .events, .diagnostics])
        for page in BusStopLink.Page.allCases {
            #expect(TopologySidebarItem(automationName: page.rawValue) == TopologySidebarItem(page))
        }
        #expect(TopologySidebarItem(automationName: "port") == nil)
        #expect(TopologySidebarItem(automationName: "") == nil)
    }
}
