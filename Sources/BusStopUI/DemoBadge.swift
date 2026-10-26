import SwiftUI

/// Small "DEMO" capsule shown while demo mode is on.
public struct DemoBadge: View {
    public init() {}

    public var body: some View {
        Text("DEMO")
            .tracking(1)
            .lagoonFont(size: 9, weight: .heavy, design: .rounded)
            .foregroundStyle(Lagoon.onAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Lagoon.accent))
            .help("Showing a demo scenario. Turn off in Settings › Advanced.")
    }
}
