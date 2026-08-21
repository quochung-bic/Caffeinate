import AppKit
import SwiftUI

/// Cửa sổ chỉ tồn tại khi tiến trình được khởi chạy với cờ
/// `LaunchEnvironment.uiTestingArgument`.
///
/// Vì sao cần nó: Caffeinate là app thanh menu, và panel của `MenuBarExtra` là
/// một `NSPanel` do hệ thống quản lý — `XCUIApplication` không mở được nó bằng
/// cách nào đủ ổn định để làm nền cho một bộ test. Không có cửa sổ nào thì
/// `launch()` còn hỏng ngay từ đầu với "Failed to activate".
///
/// Điều quan trọng: cửa sổ này KHÔNG dựng một giao diện riêng cho test. Nó host
/// đúng cái `ControlPanel` mà người dùng thật nhìn thấy, nên test vẫn đi qua
/// đường dây thật (nút → CaffeineController → state) chứ không kiểm chứng một
/// bản sao chỉ tồn tại lúc test.
@MainActor
final class UITestHarnessWindow {
    private let window: NSWindow

    init(content: some View) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Caffeinate"
        let hosting = NSHostingView(rootView: content)
        window.contentView = hosting

        // Co theo nội dung: panel rộng 288pt còn cửa sổ Cài đặt rộng 500pt, và
        // một cửa sổ hẹp hơn nội dung sẽ cắt mất chính những control cần test.
        //
        // Kẹp sàn lại: ngay sau khi gán, `fittingSize` có thể còn bằng 0 vì
        // SwiftUI chưa chạy lượt bố cục nào. Đã vấp — cửa sổ ra 0×0, không
        // control nào chạm tới được, và cả bộ test đỏ với thông báo "cửa sổ
        // không hiện ra" trong khi nó có hiện, chỉ là rỗng.
        let fitting = hosting.fittingSize
        window.setContentSize(NSSize(
            width: max(fitting.width, 520),
            height: max(fitting.height, 560)
        ))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
