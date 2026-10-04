import BusStopCore
import SwiftUI

/// Content of the menu bar popover. Placeholder; implemented by the app shell.
struct PopoverView: View {
    var store: PortStore

    var body: some View {
        Text("Bus Stop")
            .frame(width: Lagoon.popoverWidth, height: 200)
    }
}
