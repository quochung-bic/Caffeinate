#!/usr/bin/env swift
//
// GenerateAppIcon.swift — generates the whole app icon set from code.
//
//     swift Scripts/GenerateAppIcon.swift
//
// Why the icon is source rather than a PNG checked into the repo: a binary
// image cannot explain why it looks the way it does, cannot be reviewed in a
// diff, and cannot be revised once whoever drew it has moved on. In this form,
// changing the background colour or a stroke width is a one-line edit and a
// re-run — and every size comes from the same vector drawing, so they can never
// drift apart.
//
// The shapes deliberately match `MenuBarIcon` and `CoffeeCup` in the app: the
// same cup of coffee appears in three places (Dock/Finder, menu bar, panel), and
// the user should recognise it instantly as one thing.

import AppKit
import CoreGraphics
import Foundation

// MARK: - The macOS icon grid

/// A 1024 canvas with the 824 icon body centred in it. This is Apple's grid for
/// macOS icons: the 100pt margin on each side is not wasted space but room for
/// the shadow, and it keeps the icon correctly proportioned next to its
/// neighbours in the Dock. An icon that runs to the edge looks noticeably larger
/// than the ones beside it — the single most common mistake in a hand-drawn
/// icon.
let canvas: CGFloat = 1024
let bodyInset: CGFloat = 100
let bodySize = canvas - bodyInset * 2

// MARK: - Palette
//
// Warm brown, not black. A neutral black background is safe to the point of
// being invisible; real coffee colour makes the icon recognisable from a
// distance and matches the app's own material.

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let backgroundTop     = srgb(0.87, 0.62, 0.35)   // caramel catching the light
let backgroundBottom  = srgb(0.37, 0.20, 0.11)   // espresso in shadow
let porcelainTop      = srgb(0.99, 0.97, 0.93)
let porcelainBottom   = srgb(0.90, 0.85, 0.78)
let brewDark          = srgb(0.20, 0.10, 0.05)
let brewLight         = srgb(0.42, 0.23, 0.12)
let crema             = srgb(0.76, 0.53, 0.30)

// MARK: - Geometry

/// A squircle (superellipse), not a rounded rect.
///
/// macOS icon corners have CONTINUOUS curvature: the radius eases in rather
/// than jumping from straight to a circular arc. A plain `CGPath(roundedRect:)`
/// is visibly off at 512pt and above — the edge looks slightly bulged next to
/// the system icons around it.
func squirclePath(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let cx = rect.midX
    let cy = rect.midY
    let steps = 720

    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(t)
        let s = sin(t)
        let x = cx + a * copysign(pow(abs(c), 2 / n), c)
        let y = cy + b * copysign(pow(abs(s), 2 / n), s)
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// The cup body, tapering toward the base and rounded at the foot.
/// Coordinates are in the 1024 space with the origin at TOP-LEFT (flipped when
/// drawing).
struct Cup {
    static let rimY: CGFloat = 366
    static let baseY: CGFloat = 668
    static let rimHalfWidth: CGFloat = 176
    static let baseHalfWidth: CGFloat = 150
    static let centerX: CGFloat = 462   // offset left to leave room for the handle
    static let rimEllipseHeight: CGFloat = 62

    static func halfWidth(atY y: CGFloat) -> CGFloat {
        let t = (y - rimY) / (baseY - rimY)
        return rimHalfWidth + (baseHalfWidth - rimHalfWidth) * t
    }

    /// The cup's outline: two tapered walls, a rounded foot, an elliptical rim.
    static func bodyPath(flip: (CGPoint) -> CGPoint) -> CGPath {
        let path = CGMutablePath()
        let rimHalf = rimEllipseHeight / 2

        // The left half of the rim, running down the left wall.
        path.move(to: flip(CGPoint(x: centerX - rimHalfWidth, y: rimY)))
        path.addLine(to: flip(CGPoint(x: centerX - baseHalfWidth, y: baseY - 46)))
        path.addCurve(
            to: flip(CGPoint(x: centerX + baseHalfWidth, y: baseY - 46)),
            control1: flip(CGPoint(x: centerX - baseHalfWidth, y: baseY + 62)),
            control2: flip(CGPoint(x: centerX + baseHalfWidth, y: baseY + 62))
        )
        path.addLine(to: flip(CGPoint(x: centerX + rimHalfWidth, y: rimY)))
        // The rim: the upper half of the ellipse, closing the shape.
        path.addCurve(
            to: flip(CGPoint(x: centerX - rimHalfWidth, y: rimY)),
            control1: flip(CGPoint(x: centerX + rimHalfWidth, y: rimY - rimHalf * 2.4)),
            control2: flip(CGPoint(x: centerX - rimHalfWidth, y: rimY - rimHalf * 2.4))
        )
        path.closeSubpath()
        return path
    }

    /// The handle: a thick arc anchored exactly on the right wall.
    static func handlePath(flip: (CGPoint) -> CGPoint) -> CGPath {
        let topY = rimY + 50
        let bottomY = rimY + 208
        let path = CGMutablePath()
        path.move(to: flip(CGPoint(x: centerX + halfWidth(atY: topY) - 8, y: topY)))
        path.addCurve(
            to: flip(CGPoint(x: centerX + halfWidth(atY: bottomY) - 8, y: bottomY)),
            control1: flip(CGPoint(x: centerX + halfWidth(atY: topY) + 184, y: topY - 12)),
            control2: flip(CGPoint(x: centerX + halfWidth(atY: bottomY) + 184, y: bottomY + 18))
        )
        return path
    }

    /// The coffee surface — an ellipse inset within the rim, the inset showing
    /// the thickness of the ceramic.
    static func brewRect() -> CGRect {
        let inset: CGFloat = 26
        return CGRect(
            x: centerX - rimHalfWidth + inset,
            y: rimY - rimEllipseHeight / 2 + inset * 0.42,
            width: (rimHalfWidth - inset) * 2,
            height: rimEllipseHeight - inset * 0.84
        )
    }
}

// MARK: - Drawing

func drawIcon(in context: CGContext) {
    // CoreGraphics has its origin at bottom-left; the geometry above is top-down.
    func flip(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: canvas - point.y) }
    func flipRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: canvas - rect.maxY, width: rect.width, height: rect.height)
    }

    let space = CGColorSpaceCreateDeviceRGB()
    let body = CGRect(x: bodyInset, y: bodyInset, width: bodySize, height: bodySize)
    let shape = squirclePath(in: body)

    // A soft shadow under the icon body. Kept light: macOS already applies its
    // own Dock shadow, and stacking a heavy one on top makes the icon look
    // pasted onto the background.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 34,
                      color: srgb(0, 0, 0, 0.28))
    context.addPath(shape)
    context.setFillColor(backgroundBottom)
    context.fillPath()
    context.restoreGState()

    // Background: a vertical gradient plus a highlight raking in from the top
    // left — enough to give the surface depth without tipping into gloss.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [backgroundTop, backgroundBottom] as CFArray,
                                 locations: [0, 1]) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: body.midX, y: body.maxY),
            end: CGPoint(x: body.midX, y: body.minY),
            options: []
        )
    }
    if let sheen = CGGradient(colorsSpace: space,
                              colors: [srgb(1, 1, 1, 0.22), srgb(1, 1, 1, 0)] as CFArray,
                              locations: [0, 1]) {
        context.drawRadialGradient(
            sheen,
            startCenter: CGPoint(x: body.minX + body.width * 0.28, y: body.maxY - body.height * 0.12),
            startRadius: 0,
            endCenter: CGPoint(x: body.minX + body.width * 0.28, y: body.maxY - body.height * 0.12),
            endRadius: body.width * 0.72,
            options: []
        )
    }
    context.restoreGState()

    // The handle is drawn before the body so the body covers both of its ends
    // and the joint never shows a blunt stub.
    context.saveGState()
    context.setLineWidth(46)
    context.setLineCap(.round)
    context.setStrokeColor(porcelainTop)
    context.addPath(Cup.handlePath(flip: flip))
    context.strokePath()
    context.restoreGState()

    // The cup body: a ceramic gradient so the form reads as volume rather than
    // a flat white patch.
    let cupBody = Cup.bodyPath(flip: flip)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 26,
                      color: srgb(0.16, 0.07, 0.02, 0.35))
    context.addPath(cupBody)
    context.setFillColor(porcelainTop)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(cupBody)
    context.clip()
    if let porcelain = CGGradient(colorsSpace: space,
                                  colors: [porcelainTop, porcelainBottom] as CFArray,
                                  locations: [0, 1]) {
        context.drawLinearGradient(
            porcelain,
            start: flip(CGPoint(x: 0, y: Cup.rimY)),
            end: flip(CGPoint(x: 0, y: Cup.baseY + 40)),
            options: []
        )
    }
    context.restoreGState()

    // Coffee: an ellipse darkening toward the far edge, with a thin band of
    // crema nearer the front so the surface reads as liquid rather than a hole.
    let brew = flipRect(Cup.brewRect())
    context.saveGState()
    context.addEllipse(in: brew)
    context.clip()
    if let liquid = CGGradient(colorsSpace: space,
                               colors: [brewLight, brewDark] as CFArray,
                               locations: [0, 1]) {
        context.drawLinearGradient(
            liquid,
            start: CGPoint(x: brew.midX, y: brew.maxY),
            end: CGPoint(x: brew.midX, y: brew.minY),
            options: []
        )
    }
    context.restoreGState()

    context.saveGState()
    context.addEllipse(in: brew.insetBy(dx: 14, dy: 5))
    context.setStrokeColor(crema.copy(alpha: 0.55) ?? crema)
    context.setLineWidth(7)
    context.strokePath()
    context.restoreGState()
}

// MARK: - Output

func renderPNG(size: Int) -> Data {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Could not create a CGContext at \(size)×\(size)") }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    // Always draw in the 1024 space and scale, rather than redrawing per size:
    // every size is the same drawing and they cannot drift apart.
    let scale = CGFloat(size) / canvas
    context.scaleBy(x: scale, y: scale)
    drawIcon(in: context)

    guard let image = context.makeImage() else { fatalError("Could not build the image") }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode the PNG")
    }
    return data
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("Caffeinate/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let url = iconSet.appendingPathComponent("icon_\(size).png")
    try renderPNG(size: size).write(to: url)
    print("✓ icon_\(size).png")
}

// Contents.json is generated alongside the images: letting the two drift apart
// is a silent failure — Xcode emits a mild warning and then ships an icon set
// with sizes missing.
let entries: [(idiom: String, size: String, scale: String, file: Int)] = [
    ("mac", "16x16", "1x", 16),   ("mac", "16x16", "2x", 32),
    ("mac", "32x32", "1x", 32),   ("mac", "32x32", "2x", 64),
    ("mac", "128x128", "1x", 128), ("mac", "128x128", "2x", 256),
    ("mac", "256x256", "1x", 256), ("mac", "256x256", "2x", 512),
    ("mac", "512x512", "1x", 512), ("mac", "512x512", "2x", 1024),
]
let images = entries.map { entry in
    """
        { "idiom" : "\(entry.idiom)", "scale" : "\(entry.scale)", "size" : "\(entry.size)", "filename" : "icon_\(entry.file).png" }
    """.trimmingCharacters(in: .whitespaces)
}
let contents = """
{
  "images" : [
    \(images.joined(separator: ",\n    "))
  ],
  "info" : { "author" : "Scripts/GenerateAppIcon.swift", "version" : 1 }
}

"""
try contents.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("✓ Contents.json")
