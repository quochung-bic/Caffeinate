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

    init() {
        // App.init chạy trên main thread nhưng chưa được đánh dấu isolated,
        // nên phải nói tường minh thay vì bỏ qua cảnh báo.
        MainActor.assumeIsolated { LaunchEnvironment.applyActivationPolicy() }
    }

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

/// Những thứ chỉ phụ thuộc vào cách tiến trình được khởi chạy.
enum LaunchEnvironment {
    static let uiTestingArgument = "-CaffeinateUITesting"
    static let uiTestWindowID = "ui-test-harness"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    /// Bề mặt nào được đưa vào cửa sổ test. Cửa sổ Cài đặt là một `Settings`
    /// scene mà XCUITest không mở được từ ngoài, nên nó cần đường vào riêng —
    /// nếu không thì toàn bộ cửa sổ đó không có test nào, và đúng chỗ ấy đã có
    /// một lỗi trợ năng lọt qua: bốn công tắc cờ đều không có nhãn.
    enum TestSurface: String {
        case panel
        case settings
    }

    /// Đọc thẳng từ đối số tiến trình chứ không qua `UserDefaults`.
    ///
    /// Miền đối số của `NSUserDefaults` gom theo cặp `-khoá giá trị`, mà
    /// `-CaffeinateUITesting` là một cờ trần không có giá trị — nó nuốt luôn
    /// token đứng sau. Đã vấp: cờ bề mặt đặt ngay sau nó thì không bao giờ đọc
    /// ra được, và app lặng lẽ mở panel thay vì cửa sổ Cài đặt.
    static var testSurface: TestSurface {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: surfaceArgument),
              index + 1 < arguments.count,
              let surface = TestSurface(rawValue: arguments[index + 1])
        else { return .panel }
        return surface
    }

    static let surfaceArgument = "-CaffeinateUITestSurface"

    /// `LSUIElement` trong Info.plist đã đặt app ở chế độ phụ trợ. Chỉ khi chạy
    /// UI test mới nâng lên `.regular`, vì tiến trình chạy test cần app có cửa
    /// sổ thật để "activate" — một app phụ trợ không cửa sổ sẽ làm
    /// `XCUIApplication.launch()` thất bại với "Failed to activate".
    @MainActor
    static func applyActivationPolicy() {
        guard isUITesting else { return }
        NSApplication.shared.setActivationPolicy(.regular)
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
    @ObservationIgnored private var uiTestHarness: UITestHarnessWindow?

    func install(
        controller: CaffeineController,
        expiryAlert: TimerExpiryAlert,
        language: LanguagePreference
    ) {
        guard !installed else { return }
        installed = true

        if LaunchEnvironment.isUITesting {
            switch LaunchEnvironment.testSurface {
            case .panel:
                uiTestHarness = UITestHarnessWindow(
                    content: ControlPanel(controller: controller, expiryAlert: expiryAlert)
                        .environment(\.locale, language.locale)
                )
            case .settings:
                uiTestHarness = UITestHarnessWindow(
                    content: SettingsView(controller: controller, language: language)
                        .environment(\.locale, language.locale)
                )
            }
        }

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
