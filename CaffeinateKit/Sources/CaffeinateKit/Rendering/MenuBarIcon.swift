import AppKit

/// The minimum needed to draw the icon. Kept separate from `CaffeineState` so
/// the drawing code does not depend on the whole state model.
///
/// `progress` is QUANTIZED in the initializer. The menu bar icon is 18pt tall
/// and the inside of the cup only about 8.8pt — 18 pixels on a 2x display. Any
/// change smaller than 1/32 lands on the same pixel, so keeping a continuous
/// value would produce endless states that are nominally distinct and visually
/// identical. Quantizing turns this type into a usable cache key, which is why
/// an eight-hour timer builds 32 images instead of 28,800.
public struct MenuBarIconState: Equatable, Hashable, Sendable {
    /// Distinguishable coffee levels. See the explanation above.
    public static let progressSteps = 32.0

    public let isActive: Bool
    /// Fraction of time remaining, 0...1, clamped and quantized.
    /// `nil` means on indefinitely.
    public let progress: Double?
    public let hasError: Bool

    public init(isActive: Bool, progress: Double?, hasError: Bool) {
        self.isActive = isActive
        self.hasError = hasError
        self.progress = progress.map { raw in
            let clamped = min(max(raw, 0), 1)
            return (clamped * Self.progressSteps).rounded() / Self.progressSteps
        }
    }
}

/// Draws the menu bar icon with AppKit. Every stroke uses black plus alpha and
/// the image is marked as a template — macOS recolours it for light and dark
/// mode and for the menu bar tint. Never hard-code a colour here.
///
/// No display strings live in this file: the accessibility description is
/// passed in by the app layer, which is the layer that owns wording.
public enum MenuBarIcon {

    public static let size = NSSize(width: 18, height: 18)

    // MARK: - Cache
    //
    // Building an NSImage allocates a bitmap and replays the whole drawing
    // path. The menu bar label is re-evaluated every second during a countdown,
    // so skipping the cache would pay that cost 3,600 times an hour for a
    // near-identical image. The state space is small (roughly 70 combinations)
    // so a plain lookup table is enough; the limit below only guards against a
    // leak if more steps are added later.

    @MainActor private static var cache: [MenuBarIconState: NSImage] = [:]
    @MainActor private static let cacheLimit = 128

    /// Cached variant — used on the real path.
    @MainActor
    public static func cachedImage(
        for state: MenuBarIconState,
        accessibilityDescription: String
    ) -> NSImage {
        if let hit = cache[state] {
            // The accessibility description changes every second (12 minutes
            // left / 11 minutes left) while the image does not, so it is
            // reassigned rather than made part of the cache key.
            hit.accessibilityDescription = accessibilityDescription
            return hit
        }
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        let image = self.image(for: state, accessibilityDescription: accessibilityDescription)
        cache[state] = image
        return image
    }

    /// A blank of the same size, used for the "off" beat when the icon flashes
    /// at expiry. It has to keep the size, otherwise neighbouring menu bar
    /// icons jump back and forth on every beat.
    public static func blankImage(accessibilityDescription: String = "") -> NSImage {
        let image = NSImage(size: size)
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// Uncached variant — pure, for tests and for anyone needing a fresh image.
    public static func image(
        for state: MenuBarIconState,
        accessibilityDescription: String = ""
    ) -> NSImage {
        let image: NSImage
        if state.hasError {
            image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: accessibilityDescription
            ) ?? NSImage(size: size)
        } else {
            image = NSImage(size: size, flipped: false) { rect in
                draw(state, in: rect)
                return true
            }
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    // MARK: - Cup geometry (18×18 design space, origin at TOP-LEFT)
    //
    // The same cup as `CoffeeCup` in the app, reduced for 18pt: no saucer and
    // no steam, keeping the rim, the tapered body and the handle — at this size
    // more detail only muddies the icon. The coffee level is still the progress
    // bar, exactly as in the panel.

    private static let rimY: CGFloat = 5.0
    private static let baseY: CGFloat = 13.8
    private static let rimHalfWidth: CGFloat = 4.1
    private static let baseHalfWidth: CGFloat = 3.1
    private static let cupCenterX: CGFloat = 7.0
    private static let lineWidth: CGFloat = 1.25

    /// The cup body. `inset` > 0 yields the inner wall, used as the clip region
    /// for the coffee so the level never spills onto the outline itself: at
    /// 18pt, filling flush to the edge turns the icon into a black blob and the
    /// cup shape disappears.
    private static func cupPath(
        inset: CGFloat,
        transform point: (CGFloat, CGFloat) -> NSPoint
    ) -> NSBezierPath {
        let top = rimY + inset
        let bottom = baseY - inset * 0.8
        let topHalf = rimHalfWidth - inset
        let bottomHalf = baseHalfWidth - inset

        let path = NSBezierPath()
        path.move(to: point(cupCenterX - topHalf, top))
        path.line(to: point(cupCenterX - bottomHalf, bottom))
        path.curve(
            to: point(cupCenterX + bottomHalf, bottom),
            controlPoint1: point(cupCenterX - bottomHalf, bottom + 2.0),
            controlPoint2: point(cupCenterX + bottomHalf, bottom + 2.0)
        )
        path.line(to: point(cupCenterX + topHalf, top))
        path.close()
        return path
    }

    private static func draw(_ state: MenuBarIconState, in rect: NSRect) {
        let scale = rect.width / size.width
        // NSImage draws from the bottom-left; the geometry above is top-down.
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * scale, y: rect.maxY - y * scale)
        }

        // The handle is drawn first and thinner than the body: it is secondary
        // detail and must not compete with the main silhouette once the icon
        // shrinks to 18pt. Both ends land EXACTLY on the wall (which tapers, so
        // x depends on y) — even slightly inside and the handle looks like it
        // pierces the cup.
        func wallX(atY y: CGFloat) -> CGFloat {
            let t = (y - rimY) / (baseY - rimY)
            return cupCenterX + rimHalfWidth + (baseHalfWidth - rimHalfWidth) * t
        }

        let handleTop = rimY + 2.0
        let handleBottom = rimY + 5.6
        let handle = NSBezierPath()
        handle.move(to: point(wallX(atY: handleTop), handleTop))
        handle.curve(
            to: point(wallX(atY: handleBottom), handleBottom),
            controlPoint1: point(wallX(atY: handleTop) + 3.1, handleTop + 0.2),
            controlPoint2: point(wallX(atY: handleBottom) + 3.1, handleBottom - 0.3)
        )
        handle.lineWidth = lineWidth * 0.85
        handle.lineCapStyle = .round
        NSColor.black.withAlphaComponent(state.isActive ? 0.85 : 0.55).setStroke()
        handle.stroke()

        // The coffee sits inside the wall, leaving room for the outline.
        if state.isActive {
            let level = clamp(state.progress ?? 1)
            let inner = cupPath(inset: lineWidth, transform: point)
            let innerTop = rimY + lineWidth
            let innerBottom = baseY - lineWidth * 0.8
            let surface = innerBottom - level * (innerBottom - innerTop)

            if level > 0 {
                NSGraphicsContext.saveGraphicsState()
                inner.addClip()
                NSColor.black.setFill()
                NSBezierPath(rect: NSRect(
                    x: rect.minX,
                    y: point(0, innerBottom + 2.5).y,
                    width: rect.width,
                    height: (innerBottom + 2.5 - surface) * scale
                )).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }

        let body = cupPath(inset: 0, transform: point)
        body.lineWidth = lineWidth
        body.lineJoinStyle = .round
        NSColor.black.withAlphaComponent(state.isActive ? 0.95 : 0.6).setStroke()
        body.stroke()
    }
}
