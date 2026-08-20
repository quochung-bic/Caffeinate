import SwiftUI
import AppKit
import CaffeinateKit

/// Caffeinate là ứng dụng thanh menu: không có icon Dock, không có cửa sổ chính.
///
/// Hệ quả kiến trúc, không phải chi tiết thẩm mỹ — icon trên thanh menu là bề
/// mặt DUY NHẤT luôn tồn tại, nên mọi thứ phải sống suốt phiên đều móc vào đó.
/// Cửa sổ Cài đặt chỉ là một khung nhìn phụ, đóng mở lúc nào cũng được mà không
/// ảnh hưởng gì tới việc app có đang giữ máy thức hay không.
///
/// Bản trước có thêm một cửa sổ chính, và gần như toàn bộ độ phức tạp của vòng
/// đời app nằm ở chỗ điều phối nó với panel: một `NSApplicationDelegate` để
/// đoán xem lúc khởi động có nên mở cửa sổ không, một bộ theo dõi `NSPanel`
/// giành key để đóng cửa sổ khi panel bật lên, một bộ đếm yêu cầu mở cửa sổ để
/// hai yêu cầu liên tiếp không nuốt nhau. Bỏ cửa sổ chính là bỏ hết cả ba.
@main
struct CaffeinateApp: App {
    @State private var controller = CaffeineController()
    @State private var expiryAlert = TimerExpiryAlert()
    @State private var lifecycle = AppLifecycle()
    @State private var language = LanguagePreference()

    var body: some Scene {
        menuBar
        settings
    }

    private var menuBar: some Scene {
        MenuBarExtra {
            ControlPanel(controller: controller, expiryAlert: expiryAlert)
                .environment(\.locale, language.locale)
        } label: {
            MenuBarLabel(controller: controller, expiryAlert: expiryAlert, language: language)
                .task {
                    lifecycle.install(
                        controller: controller,
                        expiryAlert: expiryAlert,
                        language: language
                    )
                }
        }
        .menuBarExtraStyle(.window)
    }

    /// `SwiftUI.` là bắt buộc chứ không phải để cho đẹp: `CaffeinateKit` cũng
    /// export một kiểu tên `Settings` (bộ cấu hình người dùng), nên viết trần
    /// `Settings { … }` ở đây sẽ bắt vào nhầm kiểu và trình biên dịch báo lỗi ở
    /// một chỗ hoàn toàn khác.
    private var settings: some Scene {
        SwiftUI.Settings {
            SettingsView(controller: controller, language: language)
                .environment(\.locale, language.locale)
        }
    }

}

/// Những thứ phải được gắn đúng MỘT lần cho cả phiên chạy.
///
/// `install` cố ý idempotent. `.task` gắn nó vào nhãn của `MenuBarExtra`, và
/// SwiftUI không hứa hẹn gì về việc dựng lại view đó — bản trước không có chốt
/// này nên mỗi lần dựng lại là thêm một observer `willTerminate` nữa, tức là
/// `shutdown()` chạy nhiều lần lúc thoát.
@MainActor
@Observable
final class AppLifecycle {
    @ObservationIgnored private var installed = false
    @ObservationIgnored private var terminationObserver: NotificationObserverToken?

    func install(
        controller: CaffeineController,
        expiryAlert: TimerExpiryAlert,
        language: LanguagePreference
    ) {
        guard !installed else { return }
        installed = true

        // IOKit tự dọn assertion khi tiến trình chết, nhưng làm tường minh thì
        // hành vi suy luận được — và nó cũng dừng luôn trigger lẫn hẹn giờ.
        terminationObserver = NotificationObserverToken(
            forName: NSApplication.willTerminateNotification
        ) {
            controller.shutdown()
        }

        controller.onTimerStarted = { expiryAlert.prepareForTimer() }
        controller.onTimerExpired = {
            // Hết giờ mà vẫn active nghĩa là một luật tự động đang giữ máy
            // thức — báo đúng chuyện đó, đừng nói máy sắp ngủ.
            expiryAlert.fire(stillActive: controller.state.isActive, language: language)
        }
    }
}

/// Đăng ký quan sát theo kiểu RAII: giữ token sống đúng bằng vòng đời của
/// object này, và gỡ đăng ký khi nó chết.
///
/// Không có deinit nào ở `AppLifecycle` phải nhớ dọn — quên dọn là lỗi kinh
/// điển của `addObserver(forName:)`, và cách chắc chắn nhất để không quên là
/// làm cho việc dọn không cần ai nhớ.
private final class NotificationObserverToken: @unchecked Sendable {
    // @unchecked: token chỉ được trao lại cho removeObserver, vốn an toàn với
    // đa luồng. Không có trạng thái nào khác đi qua ranh giới actor.
    private let token: any NSObjectProtocol

    init(forName name: Notification.Name, handler: @escaping @MainActor () -> Void) {
        token = NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
