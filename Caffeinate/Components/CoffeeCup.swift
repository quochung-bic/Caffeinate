import SwiftUI

/// The coffee cup — the app's central element. The coffee level IS the progress
/// bar: full when you turn it on, draining with the time left, empty when the
/// timer ends. Steam rises only while the Mac is genuinely being held awake, so
/// one look tells you what the app is doing.
///
/// Drawn with `Canvas` rather than composed from views: the whole cup is a
/// single drawing layer, so each steam frame costs one draw pass instead of a
/// layout update.
struct CoffeeCup: View, Animatable {
    /// 0...1. How much of the cup still holds coffee.
    var fill: Double

    /// Lets SwiftUI interpolate the coffee level, so turning on pours the cup
    /// full smoothly instead of snapping to it.
    ///
    /// `nonisolated` because SwiftUI reads and writes animatableData off the
    /// main actor while animating; it only touches a `Double`, so there is no
    /// race.
    nonisolated var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }
    var isActive: Bool
    /// Steam phase, taken from an external clock so the whole app shares one beat.
    var steamPhase: Double
    var showSteam: Bool
    var size: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, canvasSize in
            // Draw in a 100×100 space and scale afterwards: every measurement
            // below reads like a technical drawing and is independent of size.
            context.scaleBy(x: canvasSize.width / 100, y: canvasSize.height / 100)
            draw(in: &context)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Cup geometry (100×100 coordinate space)

    private static let rimY: CGFloat = 32
    private static let baseY: CGFloat = 74
    private static let rimHalfWidth: CGFloat = 30
    private static let baseHalfWidth: CGFloat = 22
    private static let rimEllipseHeight: CGFloat = 7

    /// Half-width of the cup's interior at height y. The wall tapers, so the
    /// coffee surface has to narrow as the level drops — a fixed ellipse would
    /// poke out through the side.
    private static func halfWidth(atY y: CGFloat) -> CGFloat {
        let t = (y - rimY) / (baseY - rimY)
        return rimHalfWidth + (baseHalfWidth - rimHalfWidth) * t
    }

    private static var cupSilhouette: Path {
        var path = Path()
        path.move(to: CGPoint(x: 50 - rimHalfWidth, y: rimY))
        path.addLine(to: CGPoint(x: 50 - baseHalfWidth, y: baseY))
        path.addQuadCurve(
            to: CGPoint(x: 50 + baseHalfWidth, y: baseY),
            control: CGPoint(x: 50, y: baseY + 12)
        )
        path.addLine(to: CGPoint(x: 50 + rimHalfWidth, y: rimY))
        path.closeSubpath()
        return path
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext) {
        let outline: Color = isActive ? .primary : .secondary
        let outlineOpacity: Double = isActive ? 0.75 : 0.45

        drawSaucer(&context, color: outline.opacity(outlineOpacity * 0.55))
        drawHandle(&context, color: outline.opacity(outlineOpacity))
        drawCoffee(&context)
        drawCupWalls(&context, color: outline.opacity(outlineOpacity))

        if showSteam {
            drawSteam(&context)
        }
    }

    private func drawCoffee(_ context: inout GraphicsContext) {
        let level = min(max(fill, 0), 1)
        guard level > 0.001 else { return }

        // The surface runs from the bottom of the interior up to just below
        // the rim — 6 units of headroom so a full cup still shows its wall
        // rather than looking filled to the brim.
        let top = Self.baseY - level * (Self.baseY - (Self.rimY + 6))
        let halfWidth = Self.halfWidth(atY: top)

        var surface = context
        surface.clip(to: Self.cupSilhouette)
        surface.fill(
            Path(CGRect(x: 0, y: top, width: 100, height: Self.baseY + 14 - top)),
            with: .linearGradient(
                Gradient(colors: [.cupCrema, .cupBrew, .cupEspresso]),
                startPoint: CGPoint(x: 0, y: top),
                endPoint: CGPoint(x: 0, y: Self.baseY + 8)
            )
        )

        // The surface ellipse is the only thing telling the eye this is liquid
        // seen slightly from above, rather than a block of colour cut flat.
        let surfaceRect = CGRect(
            x: 50 - halfWidth, y: top - 2.6,
            width: halfWidth * 2, height: 5.2
        )
        context.fill(Path(ellipseIn: surfaceRect), with: .color(.cupCrema))
        context.stroke(
            Path(ellipseIn: surfaceRect),
            with: .color(.cupEspresso.opacity(0.35)),
            lineWidth: 0.8
        )
    }

    private func drawCupWalls(_ context: inout GraphicsContext, color: Color) {
        var walls = Path()
        walls.move(to: CGPoint(x: 50 - Self.rimHalfWidth, y: Self.rimY))
        walls.addLine(to: CGPoint(x: 50 - Self.baseHalfWidth, y: Self.baseY))
        walls.addQuadCurve(
            to: CGPoint(x: 50 + Self.baseHalfWidth, y: Self.baseY),
            control: CGPoint(x: 50, y: Self.baseY + 12)
        )
        walls.addLine(to: CGPoint(x: 50 + Self.rimHalfWidth, y: Self.rimY))
        context.stroke(walls, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineJoin: .round))

        let rim = Path(ellipseIn: CGRect(
            x: 50 - Self.rimHalfWidth, y: Self.rimY - Self.rimEllipseHeight / 2,
            width: Self.rimHalfWidth * 2, height: Self.rimEllipseHeight
        ))
        context.stroke(rim, with: .color(color), lineWidth: 2.4)
    }

    private func drawHandle(_ context: inout GraphicsContext, color: Color) {
        var handle = Path()
        handle.move(to: CGPoint(x: 78, y: 40))
        handle.addCurve(
            to: CGPoint(x: 74, y: 62),
            control1: CGPoint(x: 97, y: 42),
            control2: CGPoint(x: 94, y: 60)
        )
        context.stroke(handle, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }

    private func drawSaucer(_ context: inout GraphicsContext, color: Color) {
        // Clip away the part of the saucer behind the cup. The cup is an open
        // outline, so a full ellipse would run straight through its body and
        // read as a wire rather than a saucer.
        var saucer = context
        saucer.clip(to: Self.cupSilhouette, options: .inverse)
        saucer.stroke(
            Path(ellipseIn: CGRect(x: 8, y: 82, width: 84, height: 10)),
            with: .color(color),
            lineWidth: 2.2
        )
    }

    /// Three wisps out of phase with each other, curving along a sine and
    /// spreading as they rise — steam going straight up in step looks like a
    /// picket fence, not like heat.
    private func drawSteam(_ context: inout GraphicsContext) {
        let wisps: [(x: CGFloat, amplitude: CGFloat, offset: Double)] = [
            (38, 3.4, 0), (50, 4.2, 2.1), (62, 3.0, 4.2),
        ]

        for wisp in wisps {
            let localPhase = steamPhase + wisp.offset
            // Each wisp drifts up, fades out and repeats — the fractional part
            // of the phase acts as the wisp's age.
            let age = localPhase.truncatingRemainder(dividingBy: 1)
            let rise = CGFloat(age) * 8

            var path = Path()
            for step in 0...16 {
                let t = CGFloat(step) / 16
                let y = 26 - t * 22 - rise
                let x = wisp.x + sin(t * 3.4 + localPhase * 2) * wisp.amplitude * t
                if step == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Dense at the base, dissolving toward the top; the age envelope
            // makes each wisp appear and vanish smoothly instead of jumping
            // when it loops.
            let envelope = sin(age * .pi)
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [
                        .cupSteam.opacity(0.0),
                        .cupSteam.opacity(0.55 * envelope),
                    ]),
                    startPoint: CGPoint(x: 0, y: 2),
                    endPoint: CGPoint(x: 0, y: 26)
                ),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

extension Color {
    /// The coffee palette. Used only for the liquid and the steam — everything
    /// else in the app stays system-coloured, so the cup is the one element
    /// with a colour of its own.
    static let cupEspresso = Color(red: 0.20, green: 0.11, blue: 0.07)
    static let cupBrew = Color(red: 0.42, green: 0.23, blue: 0.13)
    static let cupCrema = Color(red: 0.80, green: 0.56, blue: 0.32)
    static let cupSteam = Color(red: 0.78, green: 0.71, blue: 0.65)
}
