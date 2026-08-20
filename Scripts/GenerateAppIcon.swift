#!/usr/bin/env swift
//
// GenerateAppIcon.swift — sinh toàn bộ bộ icon ứng dụng từ mã.
//
//     swift Scripts/GenerateAppIcon.swift
//
// Vì sao icon là mã nguồn chứ không phải một file PNG chép vào repo: một tấm
// ảnh nhị phân không nói được vì sao nó trông như vậy, không review được trong
// diff, và không sửa lại được nếu người vẽ ra nó không còn ở đây. Ở dạng này,
// đổi màu nền hay độ dày nét là sửa một dòng rồi chạy lại — và mọi kích thước
// đều được sinh từ cùng một bản vẽ vector nên không bao giờ lệch nhau.
//
// Hình khối cố ý ăn khớp với `MenuBarIcon` và `CoffeeCup` trong app: cùng một
// ly cà phê xuất hiện ở ba nơi (Dock/Finder, thanh menu, panel), và người dùng
// phải nhận ra ngay đó là cùng một thứ.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Lưới icon macOS

/// Khung vẽ 1024, thân icon 824 nằm giữa. Đây là lưới Apple quy định cho icon
/// macOS: phần lề 100pt mỗi bên không phải chỗ thừa mà là chỗ cho bóng đổ và
/// cho icon đứng đúng tỉ lệ cạnh những icon khác trong Dock. Icon tràn sát mép
/// sẽ trông to hơn hẳn hàng xóm — đó là lỗi thường gặp nhất khi tự vẽ.
let canvas: CGFloat = 1024
let bodyInset: CGFloat = 100
let bodySize = canvas - bodyInset * 2

// MARK: - Bảng màu
//
// Nâu ấm, không phải đen. Nền đen trung tính là lựa chọn an toàn tới mức vô
// hình; màu cà phê thật làm icon nhận ra được từ xa và ăn khớp với chất liệu
// của chính ứng dụng.

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let backgroundTop     = srgb(0.87, 0.62, 0.35)   // caramel bắt sáng
let backgroundBottom  = srgb(0.37, 0.20, 0.11)   // espresso trong bóng
let porcelainTop      = srgb(0.99, 0.97, 0.93)
let porcelainBottom   = srgb(0.90, 0.85, 0.78)
let brewDark          = srgb(0.20, 0.10, 0.05)
let brewLight         = srgb(0.42, 0.23, 0.12)
let crema             = srgb(0.76, 0.53, 0.30)

// MARK: - Hình học

/// Squircle (siêu ellipse) chứ không phải rounded rect.
///
/// Góc bo của icon macOS có độ cong LIÊN TỤC: bán kính đổi dần chứ không nhảy
/// từ thẳng sang cung tròn. Một `CGPath(roundedRect:)` thường sẽ lệch thấy rõ ở
/// 512pt trở lên — cạnh icon trông hơi "bụng" so với các icon hệ thống bên cạnh.
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

/// Thân ly, thuôn dần xuống đáy và bo tròn ở đế.
/// Toạ độ trong hệ 1024, gốc ở góc TRÊN-TRÁI (đảo lại lúc vẽ).
struct Cup {
    static let rimY: CGFloat = 366
    static let baseY: CGFloat = 668
    static let rimHalfWidth: CGFloat = 176
    static let baseHalfWidth: CGFloat = 150
    static let centerX: CGFloat = 462   // lệch trái để chừa chỗ cho quai
    static let rimEllipseHeight: CGFloat = 62

    static func halfWidth(atY y: CGFloat) -> CGFloat {
        let t = (y - rimY) / (baseY - rimY)
        return rimHalfWidth + (baseHalfWidth - rimHalfWidth) * t
    }

    /// Bao ngoài của ly: hai thành thuôn + đế bo tròn + vành ellipse ở trên.
    static func bodyPath(flip: (CGPoint) -> CGPoint) -> CGPath {
        let path = CGMutablePath()
        let rimHalf = rimEllipseHeight / 2

        // Nửa trái của vành, đi xuống thành trái.
        path.move(to: flip(CGPoint(x: centerX - rimHalfWidth, y: rimY)))
        path.addLine(to: flip(CGPoint(x: centerX - baseHalfWidth, y: baseY - 46)))
        path.addCurve(
            to: flip(CGPoint(x: centerX + baseHalfWidth, y: baseY - 46)),
            control1: flip(CGPoint(x: centerX - baseHalfWidth, y: baseY + 62)),
            control2: flip(CGPoint(x: centerX + baseHalfWidth, y: baseY + 62))
        )
        path.addLine(to: flip(CGPoint(x: centerX + rimHalfWidth, y: rimY)))
        // Vành: nửa cung trên của ellipse, khép kín hình.
        path.addCurve(
            to: flip(CGPoint(x: centerX - rimHalfWidth, y: rimY)),
            control1: flip(CGPoint(x: centerX + rimHalfWidth, y: rimY - rimHalf * 2.4)),
            control2: flip(CGPoint(x: centerX - rimHalfWidth, y: rimY - rimHalf * 2.4))
        )
        path.closeSubpath()
        return path
    }

    /// Quai: một cung dày bám đúng lên thành phải.
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

    /// Mặt cà phê — ellipse nằm gọn trong vành, thụt vào cho thấy độ dày sứ.
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

// MARK: - Vẽ

func drawIcon(in context: CGContext) {
    // CoreGraphics có gốc ở góc dưới-trái; bản vẽ ở trên tính từ trên xuống.
    func flip(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: canvas - point.y) }
    func flipRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: canvas - rect.maxY, width: rect.width, height: rect.height)
    }

    let space = CGColorSpaceCreateDeviceRGB()
    let body = CGRect(x: bodyInset, y: bodyInset, width: bodySize, height: bodySize)
    let shape = squirclePath(in: body)

    // Bóng đổ mềm dưới thân icon. Nhẹ thôi: macOS đã có bóng riêng cho Dock,
    // chồng thêm một cái đậm nữa là icon trông như dán đè lên nền.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 34,
                      color: srgb(0, 0, 0, 0.28))
    context.addPath(shape)
    context.setFillColor(backgroundBottom)
    context.fillPath()
    context.restoreGState()

    // Nền: gradient dọc + một vệt sáng chếch từ trên-trái, đủ để mặt phẳng có
    // chiều sâu mà không thành hiệu ứng loè loẹt.
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

    // Quai vẽ trước thân: hai đầu quai bị thân che đi, nên chỗ nối không lộ ra
    // một đoạn cụt.
    context.saveGState()
    context.setLineWidth(46)
    context.setLineCap(.round)
    context.setStrokeColor(porcelainTop)
    context.addPath(Cup.handlePath(flip: flip))
    context.strokePath()
    context.restoreGState()

    // Thân ly: gradient sứ để khối có chiều, không phải một mảng trắng phẳng.
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

    // Cà phê: ellipse tối dần về phía xa, thêm một vệt crema mảnh ở gần để mặt
    // thoáng đọc ra là chất lỏng chứ không phải một cái lỗ.
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

// MARK: - Xuất file

func renderPNG(size: Int) -> Data {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Không tạo được CGContext \(size)×\(size)") }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    // Luôn vẽ ở hệ toạ độ 1024 rồi thu phóng, thay vì vẽ lại theo từng cỡ:
    // mọi kích thước là cùng một bản vẽ, không thể lệch nhau.
    let scale = CGFloat(size) / canvas
    context.scaleBy(x: scale, y: scale)
    drawIcon(in: context)

    guard let image = context.makeImage() else { fatalError("Không dựng được ảnh") }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Không mã hoá được PNG")
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

// Contents.json sinh cùng lúc với ảnh: hai thứ này lệch nhau là lỗi im lặng —
// Xcode chỉ cảnh báo nhẹ rồi dựng ra một bộ icon thiếu cỡ.
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
