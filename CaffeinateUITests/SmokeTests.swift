import XCTest

/// Smoke test đầu-cuối ở tầng UI: click nút thật trong app và kiểm chứng trạng
/// thái "đang giữ máy thức" được phản ánh đúng trong giao diện.
///
/// Vì sao cần cờ khởi chạy: Caffeinate là app thanh menu (`LSUIElement`), không
/// có icon Dock và không có cửa sổ nào. `XCUIApplication.launch()` sẽ hỏng ngay
/// với "Failed to activate" vì không có gì để đưa lên trước, còn panel của
/// `MenuBarExtra` là `NSPanel` hệ thống mà XCUITest không mở được ổn định. Cờ
/// `-CaffeinateUITesting` nâng app lên `.regular` và mở một cửa sổ host ĐÚNG
/// `ControlPanel` mà người dùng thật thấy — không phải giao diện riêng cho test,
/// nên đường dây được kiểm chứng vẫn là đường dây thật.
///
/// Vì sao KHÔNG gọi `pmset` ở đây: tiến trình chạy UI test bị sandbox và không
/// spawn được `/usr/bin/pmset`, nên mọi lần gọi trả về rỗng — không phải tín
/// hiệu đáng tin. Phần "assertion thật hiện ra với hệ điều hành qua pmset" đã
/// được kiểm chứng ở tầng thư viện: `CaffeinateKitTests/IOKitBackingTests` tạo
/// assertion thật bằng chính `IOKitBacking` rồi đọc `pmset -g assertions`.
/// `@MainActor`: toàn bộ API của XCUITest bị cô lập về main actor, nên dưới
/// Swift 6 mỗi lần chạm tới chúng từ một method thường đều là một cảnh báo
/// đồng thời. Đánh dấu cả lớp là cách nói đúng sự thật thay vì im lặng bỏ qua.
@MainActor
final class SmokeTests: XCTestCase {

    /// Phải khớp với `LaunchEnvironment.uiTestingArgument` trong app target.
    /// Target test không import được app target nên hằng này buộc phải chép lại.
    private static let uiTestingArgument = "-CaffeinateUITesting"

    private func launchApp(language: String = "vi", locale: String = "vi_VN") -> XCUIApplication {
        let app = XCUIApplication()
        // Chốt ngôn ngữ, không để test phụ thuộc vào cài đặt của máy đang chạy.
        // Giao diện song ngữ nên cùng một nút mang nhãn "Tắt" hay "Stop" tuỳ
        // máy — test khẳng định theo nhãn thì phải nói rõ mình đang khẳng định
        // theo ngôn ngữ nào.
        app.launchArguments = [
            Self.uiTestingArgument,
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        app.launch()
        return app
    }

    func testActivatingReflectsHoldingStateInUI() throws {
        let app = launchApp()

        let indefinite = app.buttons["Bật không giới hạn"].firstMatch
        XCTAssertTrue(indefinite.waitForExistence(timeout: 10),
                      "Nút bật không giới hạn phải có mặt sau khi mở app")

        // Nút "Tắt" mang `.disabled(!isActive)`, nên `isEnabled` của nó là tín
        // hiệu active trực tiếp và đáng tin nhất.
        let stop = app.buttons["Tắt"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        XCTAssertFalse(stop.isEnabled, "Chưa bật thì nút Tắt phải bị vô hiệu")
        XCTAssertTrue(holdingLabelExists(app, "Đang tắt"),
                      "Chưa bật thì ly cà phê phải báo đang tắt")

        indefinite.click()

        XCTAssertTrue(waitForEnabled(stop, timeout: 5),
                      "Bật rồi thì nút Tắt phải hoạt động (app đang active)")
        // Ly cà phê là một phần tử trợ năng gộp; nhãn của nó phản ánh trực tiếp
        // trạng thái active dẫn xuất từ state.
        XCTAssertTrue(holdingLabelExists(app, "Đang bật, không giới hạn"),
                      "Ly cà phê phải báo đang bật không giới hạn")

        stop.click()

        XCTAssertTrue(waitForDisabled(stop, timeout: 5),
                      "Tắt rồi thì nút Tắt phải vô hiệu trở lại")
        XCTAssertTrue(holdingLabelExists(app, "Đang tắt"),
                      "Tắt rồi thì ly cà phê phải báo đang tắt")

        app.terminate()
    }

    /// Giao diện song ngữ chỉ có giá trị nếu nó thật sự đổi theo ngôn ngữ hệ
    /// thống. Test này chạy đúng luồng trên với `-AppleLanguages (en)` và khẳng
    /// định theo nhãn tiếng Anh — nên một khoá bị thiếu trong
    /// `Localizable.xcstrings` sẽ làm đỏ ngay, thay vì âm thầm rơi về tiếng
    /// Việt trên máy của người dùng nước ngoài.
    func testInterfaceIsLocalizedIntoEnglish() throws {
        let app = launchApp(language: "en", locale: "en_US")

        let indefinite = app.buttons["Turn on indefinitely"].firstMatch
        XCTAssertTrue(indefinite.waitForExistence(timeout: 10),
                      "Chạy dưới tiếng Anh thì nút phải mang nhãn tiếng Anh")

        let stop = app.buttons["Stop"].firstMatch
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        XCTAssertFalse(stop.isEnabled)

        indefinite.click()

        XCTAssertTrue(waitForEnabled(stop, timeout: 5))
        XCTAssertTrue(holdingLabelExists(app, "On, indefinitely"),
                      "Nhãn trợ năng cũng phải được dịch, không chỉ nhãn nút")

        stop.click()
        XCTAssertTrue(waitForDisabled(stop, timeout: 5))
        XCTAssertTrue(holdingLabelExists(app, "Off"))

        app.terminate()
    }

    // Vì sao KHÔNG có smoke test cho chế độ đếm ngược ở đây:
    //
    // Khi có hẹn giờ, nhãn menu bar chạy một `TimelineView` nhịp 1 Hz suốt thời
    // gian đó — đúng như thiết kế, vì icon phải vơi dần theo thời gian thực.
    // XCUITest thì chờ ứng dụng "đứng yên" trước mỗi thao tác, và một nhịp
    // không bao giờ dừng nghĩa là điều kiện đó không bao giờ đạt: mọi truy vấn
    // sau khi bấm nút thời lượng đều hết giờ chờ.
    //
    // Đây là giới hạn của công cụ chứ không phải lỗi của app, và cách đúng
    // không phải là làm hỏng app cho vừa công cụ. Toàn bộ hành vi đếm ngược
    // (đặt mốc kết thúc, tỉ lệ mực cà phê theo thời gian, kẹp thời lượng, huỷ
    // hẹn giờ khi chuyển sang không giới hạn) được kiểm chứng tất định ở
    // `CaffeinateKitTests/CaffeineControllerTests` — không cần chờ đồng hồ thật.

    // MARK: - Trợ giúp

    /// Nhãn trợ năng có thể hiện ra dưới nhiều loại phần tử tuỳ phiên bản;
    /// tìm trong toàn cây thay vì đoán đúng một loại.
    /// Ly cà phê là một phần tử trợ năng gộp; nhãn của nó phản ánh trực tiếp
    /// trạng thái active dẫn xuất từ state. Tìm theo định danh chứ không quét
    /// toàn cây theo nhãn — cây luôn có hoạt ảnh nên truy vấn diện rộng phải
    /// chờ một trạng thái đứng yên vốn không bao giờ tới.
    private func gauge(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["caffeine-gauge"].firstMatch
    }

    private func waitForGaugeLabel(
        _ app: XCUIApplication,
        _ predicateFormat: String,
        _ value: String,
        timeout: TimeInterval = 10
    ) -> Bool {
        let element = gauge(app)
        let e = expectation(
            for: NSPredicate(format: predicateFormat, value),
            evaluatedWith: element
        )
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    private func holdingLabelExists(_ app: XCUIApplication, _ label: String) -> Bool {
        waitForGaugeLabel(app, "label == %@", label)
    }

    private func holdingLabelExists(_ app: XCUIApplication, beginningWith prefix: String) -> Bool {
        waitForGaugeLabel(app, "label BEGINSWITH %@", prefix)
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let e = expectation(for: NSPredicate(format: "isEnabled == true"),
                            evaluatedWith: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    private func waitForDisabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let e = expectation(for: NSPredicate(format: "isEnabled == false"),
                            evaluatedWith: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }
}
