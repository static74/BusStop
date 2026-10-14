import AppKit
import SwiftUI

/// Hosts one of the map's controls (the zoom cluster, the Data/Power picker)
/// in its own `NSHostingView`, so AppKit tracks its `.help` tooltips on
/// their own instead of with the rest of the map.
///
/// AppKit keeps one tooltip tracker per hosting view. Over the map's empty
/// space it finds no tooltip and waits until the pointer leaves a 4-point
/// square around it. When the window server never reports the pointer
/// inside that square (seen while another tooltip was still fading out), the
/// pointer leaving it is never reported either, and no control that shares
/// the map's hosting view shows a tooltip until the pointer goes back there.
/// A control in its own hosting view is tracked from the moment the pointer
/// enters it. See docs/decisions.md, "The map's controls get their own
/// hosting views".
///
/// The hosted content does not inherit the map's environment; the values it
/// needs are passed on here.
struct GraphControlHost<Content: View>: NSViewRepresentable {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<AnyView> {
        let view = NSHostingView(rootView: root(context.environment))
        view.sizingOptions = [.intrinsicContentSize]
        return view
    }

    func updateNSView(_ view: NSHostingView<AnyView>, context: Context) {
        view.rootView = root(context.environment)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSHostingView<AnyView>, context: Context) -> CGSize? {
        nsView.fittingSize
    }

    private func root(_ environment: EnvironmentValues) -> AnyView {
        AnyView(content.environment(\.lagoonTextScale, environment.lagoonTextScale))
    }
}
