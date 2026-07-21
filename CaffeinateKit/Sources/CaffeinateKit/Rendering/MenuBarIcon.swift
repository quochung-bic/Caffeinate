import AppKit

/// Thông tin tối thiểu cần để vẽ icon. Tách khỏi `CaffeineState` để phần vẽ
/// không phụ thuộc vào toàn bộ mô hình trạng thái.
///
/// `progress` được LƯỢNG TỬ HOÁ ngay trong init. Icon menu bar cao 18pt, lòng
/// ly chỉ chừng 8.8pt — ở màn hình 2x là 18 pixel. Mọi thay đổi nhỏ hơn 1/32
/// đều rơi vào cùng một pixel, nên giữ giá trị liên tục chỉ tạo ra vô số trạng
/// thái khác nhau trên danh nghĩa mà giống hệt nhau trên màn hình. Lượng tử hoá
/// biến kiểu này thành khoá cache dùng được, và nhờ đó một lần hẹn giờ 8 tiếng
/// dựng 32 tấm ảnh thay vì 28.800 tấm.
public struct MenuBarIconState: Equatable, Hashable, Sendable {
    /// Số bậc mực cà phê phân biệt được. Xem giải thích ở trên.
    public static let progressSteps = 32.0

    public let isActive: Bool
    /// Tỉ lệ thời gian còn lại, 0...1, đã kẹp và lượng tử hoá.
    /// `nil` nghĩa là đang bật không giới hạn.
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

/// Vẽ icon menu bar bằng AppKit. Toàn bộ nét vẽ dùng đen + alpha rồi đánh dấu
/// template — macOS sẽ tự tô lại theo sáng/tối và theo tint của menu bar.
/// Không bao giờ hard-code màu ở đây.
///
/// Không có chuỗi hiển thị nào trong file này: mô tả trợ năng do tầng app
/// truyền vào, vì chỉ tầng đó mới biết ngôn ngữ người dùng đang dùng.
public enum MenuBarIcon {

    public static let size = NSSize(width: 18, height: 18)

    // MARK: - Cache
    //
    // Dựng NSImage nghĩa là cấp một bitmap và chạy lại toàn bộ đường vẽ. Nhãn
    // menu bar được đánh giá lại mỗi giây trong lúc đếm ngược, nên không cache
    // là trả cái giá đó 3.600 lần mỗi giờ cho một hình gần như không đổi.
    // Không gian trạng thái nhỏ (khoảng 70 tổ hợp) nên bảng tra đơn giản là đủ;
    // ngưỡng bên dưới chỉ để chặn rò rỉ nếu sau này thêm bậc.

    @MainActor private static var cache: [MenuBarIconState: NSImage] = [:]
    @MainActor private static let cacheLimit = 128

    /// Bản có cache — dùng cho đường chạy thật.
    @MainActor
    public static func cachedImage(
        for state: MenuBarIconState,
        accessibilityDescription: String
    ) -> NSImage {
        if let hit = cache[state] {
            // Mô tả trợ năng đổi theo từng giây (còn 12 phút / còn 11 phút) mà
            // hình thì không, nên nó được gán lại chứ không tham gia làm khoá.
            hit.accessibilityDescription = accessibilityDescription
            return hit
        }
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        let image = self.image(for: state, accessibilityDescription: accessibilityDescription)
        cache[state] = image
        return image
    }

    /// Ô trống cùng kích thước, dùng cho nhịp "tắt" khi icon nhấp nháy báo hết
    /// giờ. Phải giữ nguyên kích thước, nếu không các icon bên cạnh sẽ nhảy
    /// qua nhảy lại theo từng nhịp.
    public static func blankImage(accessibilityDescription: String = "") -> NSImage {
        let image = NSImage(size: size)
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// Bản không cache — thuần tuý, dùng cho test và cho ai cần một ảnh mới.
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

    // MARK: - Hình học ly (hệ toạ độ thiết kế 18×18, gốc ở góc TRÊN-TRÁI)
    //
    // Cùng một ly với `CoffeeCup` trong app, rút gọn cho 18pt: bỏ đĩa lót và
    // khói, giữ lại vành, thân thuôn và quai — ở cỡ này thêm chi tiết chỉ làm
    // icon đục đi. Mực cà phê vẫn là tiến trình, y như trong panel.

    private static let rimY: CGFloat = 5.0
    private static let baseY: CGFloat = 13.8
    private static let rimHalfWidth: CGFloat = 4.1
    private static let baseHalfWidth: CGFloat = 3.1
    private static let cupCenterX: CGFloat = 7.0
    private static let lineWidth: CGFloat = 1.25

    /// Thân ly. `inset` > 0 cho ra lòng ly — dùng làm vùng cắt cho cà phê, để
    /// mực cà phê không bao giờ chồm lên chính nét viền: ở 18pt mà đổ đầy sát
    /// viền thì icon biến thành một khối đen, mất hẳn hình ly.
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
        // NSImage vẽ với gốc ở góc dưới-trái; bản vẽ ở trên tính từ trên xuống.
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * scale, y: rect.maxY - y * scale)
        }

        // Quai vẽ trước và mảnh hơn thân: nó là chi tiết phụ, không được tranh
        // chấp với hình khối chính khi icon co lại còn 18pt. Hai đầu quai bám
        // ĐÚNG lên thành ly (thành thuôn nên toạ độ x đổi theo y) — lệch vào
        // trong một chút thôi là quai trông như xuyên thủng ly.
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

        // Cà phê nằm trong lòng ly, chừa hẳn một khoảng cho nét viền.
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
