import AppKit

/// Template images for the menu bar item.
///
/// The default icon is a custom-drawn bus-stop sign: a slim pole on a short
/// foot, topped by a rounded sign plate with a USB-C receptacle cut out of it.
/// Every edge sits on a whole point, so the sign stays crisp at 1x and 2x.
/// The other styles are SF Symbols. All images are templates, so the menu bar
/// tints them for light, dark and selected states.
enum StatusIcon {
    /// Canvas size in points. The menu bar is 24 pt tall.
    static let canvasSize = NSSize(width: 18, height: 18)

    /// The image for a menu bar icon style.
    static func image(for style: MenuBarIconStyle) -> NSImage {
        if let symbolName = style.symbolName,
           let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Bus Stop") {
            let configuration = NSImage.SymbolConfiguration(pointSize: pointSize(for: style), weight: .medium)
            let image = base.withSymbolConfiguration(configuration) ?? base
            image.isTemplate = true
            return image
        }
        return busStopSign()
    }

    /// The custom bus-stop sign, drawn on demand at the screen's scale.
    static func busStopSign() -> NSImage {
        let image = NSImage(size: canvasSize, flipped: false, drawingHandler: StatusIcon.drawSign(in:))
        image.isTemplate = true
        image.accessibilityDescription = "Bus Stop"
        return image
    }

    /// SF Symbols have different optical sizes; these keep them balanced
    /// against the 18 pt sign.
    private static func pointSize(for style: MenuBarIconStyle) -> CGFloat {
        switch style {
        case .busStop: return 14
        case .connector: return 14
        case .bolt: return 13
        case .grid: return 13
        }
    }

    /// Draws the sign in an 18 x 18 pt canvas (origin bottom left).
    ///
    /// `nonisolated` because AppKit may call an image's drawing handler from
    /// any thread that renders the image; it touches no shared state.
    nonisolated private static func drawSign(in rect: NSRect) -> Bool {
        // Scale in case AppKit asks for a different canvas size.
        let unit = min(rect.width, rect.height) / 18
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
            NSRect(x: rect.minX + x * unit, y: rect.minY + y * unit, width: width * unit, height: height * unit)
        }

        NSColor.black.setFill()

        // Sign plate with the receptacle opening cut out (even-odd fill).
        let plate = NSBezierPath(roundedRect: box(2, 9, 14, 8), xRadius: 2.5 * unit, yRadius: 2.5 * unit)
        let opening = NSBezierPath(roundedRect: box(5, 11, 8, 4), xRadius: 2 * unit, yRadius: 2 * unit)
        plate.append(opening)
        plate.windingRule = .evenOdd
        plate.fill()

        // The receptacle's tongue, floating in the opening.
        NSBezierPath(roundedRect: box(7, 12, 4, 2), xRadius: 0.5 * unit, yRadius: 0.5 * unit).fill()

        // Pole, meeting the bottom edge of the plate.
        NSBezierPath(rect: box(8, 2, 2, 7)).fill()

        // Foot.
        NSBezierPath(roundedRect: box(5, 1, 8, 1), xRadius: 0.5 * unit, yRadius: 0.5 * unit).fill()
        return true
    }
}
