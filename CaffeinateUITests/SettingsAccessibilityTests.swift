import XCTest

/// Cửa sổ Cài đặt là một `Settings` scene mà XCUITest không mở được từ ngoài,
/// nên trước đây nó không có test nào — và đúng chỗ ấy đã có một lỗi lọt qua:
/// bốn công tắc cờ, picker ngôn ngữ và stepper thời lượng đều mang nhãn trợ
/// năng RỖNG. Trong `Form` trên macOS, nhãn của những control này được vẽ thành
/// một dòng chữ RIÊNG nằm cạnh chúng chứ không gắn vào chính control, nên
/// VoiceOver đọc ra bốn công tắc giống hệt nhau: "switch, on".
///
/// Bộ test lái cửa sổ đó qua `-CaffeinateUITestSurface settings`.
///
/// Chỉ dùng truy vấn theo LOẠI CONTROL (`switches`, `popUpButtons`,
/// `steppers`), không dùng `staticTexts`: truy vấn tập chữ trên cửa sổ này hết
/// giờ chờ một cách ổn định. Điều đó cũng không mất mát gì — thứ đáng khẳng
/// định ở đây là control có nhãn hay không, mà nhãn thì nằm trên control.
@MainActor
final class SettingsAccessibilityTests: XCTestCase {

    private func launchSettings(language: String = "vi", locale: String = "vi_VN") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-CaffeinateUITesting",
            "-CaffeinateUITestSurface", "settings",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ]
        app.launch()

        // Chờ cửa sổ có mặt trước khi truy vấn phần tử bên trong: lượt chụp cây
        // trợ năng đầu tiên có thể rơi vào lúc chưa có cửa sổ nào, và nó không
        // tự thử lại.
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15),
                      "Cửa sổ Cài đặt phải hiện ra")
        return app
    }

    /// Một control không có nhãn là một control mà người dùng VoiceOver không
    /// dùng được. Kiểm tra theo lớp chứ không liệt kê từng cái: thêm một
    /// `Toggle` mới mà quên nhãn thì test này đỏ ngay, không cần ai nhớ.
    func testEveryControlHasAnAccessibilityLabel() {
        let app = launchSettings()
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 10),
                      "Tab Chung phải có các công tắc cờ")

        // Đi qua từng tab: mỗi tab có control riêng, và tab nào không được mở
        // ra thì nội dung của nó không nằm trong cây trợ năng để mà kiểm tra.
        for tab in ["Chung", "Tự động", "Khởi động"] {
            let button = app.radioButtons[tab].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Thiếu tab \"\(tab)\"")
            button.click()

            assertAllLabelled(app.switches, kind: "công tắc ở tab \(tab)")
            assertAllLabelled(app.checkBoxes, kind: "checkbox ở tab \(tab)")
            assertAllLabelled(app.popUpButtons, kind: "menu chọn ở tab \(tab)")
            assertAllLabelled(app.steppers, kind: "stepper ở tab \(tab)")
        }

        app.terminate()
    }

    /// Bốn cờ giữ thức phải nhận ra được TỪNG CÁI qua nhãn trợ năng — không chỉ
    /// "có nhãn" mà là nhãn đúng của riêng nó.
    func testHoldFlagsAreIndividuallyIdentifiable() {
        let app = launchSettings()
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 10))

        for name in ["Hệ thống", "Màn hình", "Đĩa", "Idle"] {
            XCTAssertTrue(toggleExists(app, labelled: name),
                          "Không tìm thấy công tắc mang nhãn \"\(name)\"")
        }
        XCTAssertTrue(app.popUpButtons["Ngôn ngữ"].firstMatch.exists,
                      "Picker ngôn ngữ phải mang nhãn của nó")
        XCTAssertTrue(app.steppers["Thời lượng tuỳ chỉnh"].firstMatch.exists,
                      "Stepper thời lượng phải mang nhãn của nó")

        app.terminate()
    }

    /// Cửa sổ Cài đặt cũng phải đổi ngôn ngữ, không chỉ panel — kể cả nhãn trợ
    /// năng, vì chúng được gắn tay nên rất dễ bị bỏ quên khi dịch.
    func testSettingsWindowIsLocalized() {
        let app = launchSettings(language: "en", locale: "en_US")
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 10))

        for name in ["System", "Display", "Disk", "Idle"] {
            XCTAssertTrue(toggleExists(app, labelled: name),
                          "Không tìm thấy công tắc mang nhãn tiếng Anh \"\(name)\"")
        }
        XCTAssertTrue(app.popUpButtons["Language"].firstMatch.exists)
        XCTAssertFalse(app.popUpButtons["Ngôn ngữ"].firstMatch.exists,
                       "Không được còn sót nhãn tiếng Việt")

        app.terminate()
    }

    /// macOS dựng `Toggle` trong Form thành `Switch` hay `CheckBox` tuỳ phiên
    /// bản và tuỳ kiểu Form; chấp nhận cả hai thay vì khoá chặt vào một loại.
    private func toggleExists(_ app: XCUIApplication, labelled label: String) -> Bool {
        app.switches[label].firstMatch.exists || app.checkBoxes[label].firstMatch.exists
    }

    private func assertAllLabelled(_ query: XCUIElementQuery, kind: String) {
        for index in 0..<query.count {
            let element = query.element(boundBy: index)
            XCTAssertFalse(
                element.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(kind) thứ \(index) không có nhãn trợ năng (value=\(element.value ?? "nil"))"
            )
        }
    }
}
