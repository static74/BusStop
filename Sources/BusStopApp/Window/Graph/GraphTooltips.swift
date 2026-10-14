import AppKit
import SwiftUI

// The map's own tooltips for its chips and badges. The 30 fps link pulses
// keep the system's tooltips from appearing anywhere over the map, and those
// on a card's chips never appeared at all, so the map finds the chip under
// the pointer and draws the tooltip itself (see docs/decisions.md).
//
// Each chip publishes its rectangle in layout coordinates, measured before
// the zoom. The pointer is turned into a layout point the same way, so
// finding the chip under it needs no geometry from the drawing group.

/// A chip or badge on the map and its tooltip, in layout coordinates.
nonisolated struct GraphTooltipRegion: Equatable, Sendable {
    /// Unique on the map: the card or link, then the chip ("port:3/power").
    var id: String
    var text: String
    var rect: CGRect
}

/// Every chip on the map that has a tooltip.
nonisolated struct GraphTooltipRegionsKey: PreferenceKey {
    static let defaultValue: [GraphTooltipRegion] = []

    static func reduce(value: inout [GraphTooltipRegion], nextValue: () -> [GraphTooltipRegion]) {
        value += nextValue()
    }
}

/// The geometry and timing of the map's tooltips.
nonisolated enum GraphTooltip {
    /// The coordinate space of one card (or one link chip) before the zoom.
    /// Chips measure themselves in it, and a card reports the pointer in it.
    static let space = "graphTooltipSpace"

    /// How long the pointer rests on a chip before its tooltip appears: the
    /// system's `NSInitialToolTipDelay` (milliseconds), one second if unset.
    static var initialDelay: Duration {
        let milliseconds = UserDefaults.standard.double(forKey: "NSInitialToolTipDelay")
        return .milliseconds(milliseconds > 0 ? milliseconds : 1000)
    }

    /// Moving to another chip shortly after a tooltip showed brings its
    /// tooltip up this quickly instead, as the system does.
    static let switchDelay: Duration = .milliseconds(100)
    static let warmPeriod: Duration = .milliseconds(500)

    /// Gap between the chip and the tooltip.
    static let gap: CGFloat = 6
    /// The tooltip keeps this far from the map's edges.
    static let margin: CGFloat = 8
    /// Height kept clear above the map's bottom edge for the legend and zoom
    /// controls; a tooltip that would reach into it goes above its chip.
    static let bottomInset: CGFloat = 64
    static let maxWidth: CGFloat = 280

    /// The smallest region containing `point`, so a chip wins over anything
    /// larger behind it.
    static func region(at point: CGPoint, in regions: [GraphTooltipRegion]) -> GraphTooltipRegion? {
        regions.lazy
            .filter { $0.rect.contains(point) }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
    }

    /// Where a layout rectangle appears in the map view.
    static func screenRect(_ rect: CGRect, camera: GraphCamera) -> CGRect {
        let origin = camera.screenPoint(rect.origin)
        return CGRect(x: origin.x, y: origin.y, width: rect.width * camera.scale, height: rect.height * camera.scale)
    }

    /// The top-left corner of a tooltip of `size` for a chip at `anchor` (on
    /// screen), in a map of `bounds`: centred under the chip, above it when
    /// it would reach into the controls at the bottom, and kept inside the
    /// map.
    static func origin(of size: CGSize, for anchor: CGRect, in bounds: CGSize) -> CGPoint {
        var y = anchor.maxY + gap
        if y + size.height > bounds.height - bottomInset {
            y = anchor.minY - gap - size.height
        }
        let x = anchor.midX - size.width / 2
        return CGPoint(x: min(max(x, margin), max(margin, bounds.width - margin - size.width)),
                       y: max(y, margin))
    }
}

extension View {
    /// Publishes this view as a tooltip region, measured in the enclosing
    /// `GraphTooltip.space`.
    func graphTooltip(_ text: String, id: String) -> some View {
        modifier(GraphTooltipModifier(text: text, id: id))
    }
}

/// Keeps the view's rectangle in `GraphTooltip.space` and publishes it.
/// That rectangle moves only when the card's content does, not when the map
/// pans or zooms, so nothing here runs for a frame of a pan or zoom.
struct GraphTooltipModifier: ViewModifier {
    var text: String
    var id: String
    @State private var rect: CGRect?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GraphTooltip.space)) } action: { rect = $0 }
            .preference(key: GraphTooltipRegionsKey.self,
                        value: rect.map { [GraphTooltipRegion(id: id, text: text, rect: $0)] } ?? [])
    }
}

// MARK: - State

/// The chip under the pointer and the tooltip on screen.
///
/// Only `shown` is observed, and only `GraphTooltipOverlay` reads it, so the
/// map's body never runs for a tooltip. Everything else changes with every
/// pointer move or snapshot and is kept out of observation. `shown` changes
/// only when a tooltip appears, disappears or its text changes.
@Observable
final class GraphTooltipState {
    private(set) var shown: GraphTooltipRegion?

    /// Overrides `GraphTooltip.initialDelay`, which is read when needed.
    @ObservationIgnored var initialDelay: Duration?
    @ObservationIgnored var switchDelay = GraphTooltip.switchDelay

    @ObservationIgnored private var regions: [GraphTooltipRegion] = []
    /// The pointer in layout coordinates, from whichever of the card under
    /// it and the map's hit layer reported last.
    @ObservationIgnored private var pointer: CGPoint?
    @ObservationIgnored private var cardPointer: CGPoint?
    /// The node whose card reported `cardPointer`. Only that card can clear
    /// it, since the card left can report after the card entered.
    @ObservationIgnored private var cardOwner: String?
    @ObservationIgnored private var mapPointer: CGPoint?
    @ObservationIgnored private var hoveredID: String?
    /// False while the window does not appear active: nothing is shown.
    @ObservationIgnored private var isActive = true
    /// Set by a click or a camera move: the chip under the pointer shows no
    /// tooltip until the pointer leaves it.
    @ObservationIgnored private var isSuppressed = false
    @ObservationIgnored private var lastHidden: ContinuousClock.Instant?
    @ObservationIgnored private var timer: Task<Void, Never>?

    func setRegions(_ regions: [GraphTooltipRegion]) {
        self.regions = regions
        refresh()
    }

    /// The pointer over the card of node `node`, in layout coordinates; nil
    /// when it leaves.
    func cardPointerMoved(_ node: String, to point: CGPoint?) {
        if let point {
            cardOwner = node
            cardPointer = point
            pointer = point
        } else {
            guard cardOwner == node else { return }
            cardOwner = nil
            cardPointer = nil
            pointer = mapPointer
        }
        refresh()
    }

    /// The pointer over the map's hit layer, in layout coordinates; nil when
    /// it leaves.
    func mapPointerMoved(to point: CGPoint?) {
        mapPointer = point
        pointer = point ?? cardPointer
        refresh()
    }

    /// The map moved under the pointer: the pointer's layout position is
    /// unknown until it reports again, so no chip can be shown for it.
    func cameraMoved() {
        pointer = nil
        cardPointer = nil
        cardOwner = nil
        mapPointer = nil
        dismiss()
    }

    /// Whether the window appears active. While it does not, the tooltip
    /// stays hidden.
    func setActive(_ isActive: Bool) {
        guard isActive != self.isActive else { return }
        self.isActive = isActive
        dismiss()
    }

    /// Hides the tooltip until the pointer moves to another chip.
    func dismiss() {
        timer?.cancel()
        timer = nil
        if shown != nil { shown = nil }
        isSuppressed = hoveredID != nil
    }

    private func refresh() {
        hover(pointer.flatMap { GraphTooltip.region(at: $0, in: regions) })
    }

    private func hover(_ region: GraphTooltipRegion?) {
        guard region?.id != hoveredID else {
            // Same chip: keep its tooltip's text and place current, since
            // readings change with every snapshot.
            if let region, shown?.id == region.id, shown != region { shown = region }
            return
        }
        hoveredID = region?.id
        isSuppressed = false
        timer?.cancel()
        timer = nil
        if shown != nil {
            shown = nil
            lastHidden = .now
        }
        guard let id = region?.id else { return }
        let isWarm = lastHidden.map { ContinuousClock.now - $0 < GraphTooltip.warmPeriod } ?? false
        let delay = isWarm ? switchDelay : (initialDelay ?? GraphTooltip.initialDelay)
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.show(id)
        }
    }

    private func show(_ id: String) {
        guard id == hoveredID, !isSuppressed, isActive, let region = regions.first(where: { $0.id == id }) else { return }
        shown = region
    }
}

// MARK: - Drawing

/// The tooltip, drawn over the map outside its drawing group, so it keeps
/// its size and stays sharp at every zoom. It never takes the pointer.
struct GraphTooltipOverlay: View {
    var state: GraphTooltipState
    var camera: GraphCamera
    var size: CGSize

    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = appearsActive ? state.shown : nil
        GraphTooltipLayout(anchor: shown.map { GraphTooltip.screenRect($0.rect, camera: camera) } ?? .zero) {
            if let shown {
                GraphTooltipBubble(text: shown.text)
                    .id(shown.id)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: shown?.id)
        .allowsHitTesting(false)
        // The chips carry the same text as accessibility labels.
        .accessibilityHidden(true)
        .onChange(of: appearsActive, initial: true) { _, isActive in
            state.setActive(isActive)
        }
    }
}

/// Places the tooltip with `GraphTooltip.origin` once its size is known.
struct GraphTooltipLayout: Layout {
    /// The chip, on screen.
    var anchor: CGRect

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: GraphTooltip.maxWidth, height: nil))
            let origin = GraphTooltip.origin(of: size, for: anchor, in: bounds.size)
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}

/// A small raised card with the chip's explanation.
struct GraphTooltipBubble: View {
    var text: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Text(text)
            .lagoonFont(.subheadline)
            .foregroundStyle(Lagoon.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(shape.fill(Lagoon.surfaceRaised))
            .overlay(shape.strokeBorder(contrast == .increased ? Lagoon.accent : Lagoon.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
    }
}
