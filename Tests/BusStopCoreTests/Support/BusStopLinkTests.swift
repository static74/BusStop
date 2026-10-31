import Foundation
import Testing
@testable import BusStopCore

/// `busstop://` deep links: what widgets build and what the app accepts.
@Suite("Deep links")
struct BusStopLinkTests {
    @Test func pageLinksRoundTrip() {
        #expect(BusStopLink.page(.power).url.absoluteString == "busstop://topology/power")
        for page in BusStopLink.Page.allCases {
            #expect(BusStopLink(url: BusStopLink.page(page).url) == .page(page))
        }
    }

    @Test func portLinksRoundTrip() {
        #expect(BusStopLink.port(PortKey(type: 2, number: 1)).url.absoluteString == "busstop://port/2/1")
        for key in [PortKey(type: 2, number: 1), PortKey(type: PortKey.magSafeType, number: 1),
                    PortKey(type: PortKey.usbAType, number: 0), PortKey(type: -1, number: 12)] {
            #expect(BusStopLink(url: BusStopLink.port(key).url) == .port(key))
        }
        #expect(BusStopLink(url: URL(string: "busstop://port/2%2F1")!) == .port(PortKey(type: 2, number: 1)))
        #expect(BusStopLink(url: URL(string: "BUSSTOP://topology/events")!) == .page(.events))
    }

    @Test(arguments: [
        "https://topology/power", "busstop:topology/power", "busstop://", "busstop://topology",
        "busstop://topology/", "busstop://topology/Power", "busstop://topology/power/",
        "busstop://topology/port", "busstop://settings/general", "busstop://port", "busstop://port/",
        "busstop://port/2", "busstop://port/2/1/", "busstop://port/2/1/3", "busstop://port/02/1",
        "busstop://port/+2/1", "busstop://port/a/b", "busstop://port/2%2F", "busstop://port/%ZZ",
        "busstop://port/99999999999999999999/1", "busstop://user@port/2/1", "busstop://port:80/2/1",
    ])
    func malformedLinksAreRejected(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(BusStopLink(url: url) == nil)
    }
}
