import SwiftUI

/// Ly cà phê — phần tử trung tâm của app. Mực cà phê CHÍNH LÀ thanh tiến trình:
/// đầy khi vừa bật, vơi dần theo thời gian còn lại, cạn khi hết giờ. Khói chỉ
/// bốc khi đang thực sự giữ máy thức, nên nhìn một cái là biết app đang làm gì.
///
/// Vẽ bằng `Canvas` thay vì ghép nhiều View: cả ly là một lớp vẽ duy nhất, mỗi
/// khung hình khói chỉ tốn một lần vẽ chứ không phải một vòng cập nhật layout.
struct CoffeeCup: View, Animatable {
    /// 0...1. Phần ly còn cà phê.
    var fill: Double

    /// Cho SwiftUI nội suy mực cà phê: nhờ vậy lúc bật, cà phê được rót đầy
    /// mượt mà thay vì hiện ra đột ngột.
    ///
    /// `nonisolated` vì SwiftUI đọc/ghi animatableData ngoài main actor khi
    /// chạy animation; bản thân nó chỉ đụng một `Double` nên không có tranh chấp.
    nonisolated var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }
    var isActive: Bool
    /// Pha của khói, tính từ đồng hồ bên ngoài để cả app dùng chung một nhịp.
    var steamPhase: Double
    var showSteam: Bool
    var size: CGFloat

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, canvasSize in
            // Vẽ trong hệ toạ độ 100×100 rồi mới thu phóng: mọi số đo hình học
            // bên dưới đọc được như một bản vẽ kỹ thuật, không phụ thuộc size.
            context.scaleBy(x: canvasSize.width / 100, y: canvasSize.height / 100)
            draw(in: &context)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Hình học của ly (hệ toạ độ 100×100)

    private static let rimY: CGFloat = 32
    private static let baseY: CGFloat = 74
    private static let rimHalfWidth: CGFloat = 30
    private static let baseHalfWidth: CGFloat = 22
    private static let rimEllipseHeight: CGFloat = 7

    /// Nửa bề rộng lòng ly tại độ cao y — thành ly thuôn nên mặt cà phê phải
    /// hẹp dần khi vơi xuống, nếu vẽ ellipse cố định sẽ lòi ra ngoài thành.
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

    // MARK: - Vẽ

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

        // Mặt cà phê chạy từ đáy lòng ly lên tới ngay dưới vành — chừa 6 đơn
        // vị để khi đầy vẫn thấy thành ly, không bị "tràn tới miệng".
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

        // Ellipse mặt thoáng: thứ duy nhất nói cho mắt biết đây là chất lỏng
        // nhìn hơi chếch từ trên, chứ không phải một khối màu bị cắt ngang.
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
        // Cắt bỏ phần đĩa nằm sau ly. Ly là nét rỗng nên nếu vẽ nguyên vòng
        // ellipse thì đĩa xuyên qua thân ly, trông như dây thay vì như đĩa.
        var saucer = context
        saucer.clip(to: Self.cupSilhouette, options: .inverse)
        saucer.stroke(
            Path(ellipseIn: CGRect(x: 8, y: 82, width: 84, height: 10)),
            with: .color(color),
            lineWidth: 2.2
        )
    }

    /// Ba sợi khói lệch pha nhau, uốn theo hình sin và loe rộng khi lên cao —
    /// khói bốc thẳng đều nhau trông như hàng rào, không giống hơi nóng.
    private func drawSteam(_ context: inout GraphicsContext) {
        let wisps: [(x: CGFloat, amplitude: CGFloat, offset: Double)] = [
            (38, 3.4, 0), (50, 4.2, 2.1), (62, 3.0, 4.2),
        ]

        for wisp in wisps {
            let localPhase = steamPhase + wisp.offset
            // Mỗi sợi trôi lên rồi mờ hẳn, xong lặp lại — dùng phần thập phân
            // của pha làm "tuổi đời" của sợi khói.
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

            // Đậm ở gốc, tan dần lên đỉnh; thêm envelope theo tuổi để sợi khói
            // hiện ra và biến mất mượt chứ không nhảy khi lặp lại.
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
    /// Bảng màu cà phê. Chỉ dùng cho chất lỏng và khói — mọi thứ khác trong app
    /// vẫn là màu hệ thống, để ly là điểm nhấn duy nhất có màu riêng.
    static let cupEspresso = Color(red: 0.20, green: 0.11, blue: 0.07)
    static let cupBrew = Color(red: 0.42, green: 0.23, blue: 0.13)
    static let cupCrema = Color(red: 0.80, green: 0.56, blue: 0.32)
    static let cupSteam = Color(red: 0.78, green: 0.71, blue: 0.65)
}
