import XCTest

/// Kiểm chứng phần chuyển ngữ ở hai mức, vì chúng hỏng theo hai kiểu khác nhau:
/// một chuỗi quên dịch thì lặng lẽ rơi về tiếng Việt, còn cơ chế chuyển ngôn
/// ngữ hỏng thì đổi lựa chọn không ăn thua gì cả.
@MainActor
final class LocalizationTests: XCTestCase {

    private static let uiTestingArgument = "-CaffeinateUITesting"

    /// Phải khớp với `LanguagePreference.defaultsKey`. Target test không import
    /// được app target nên hằng này buộc phải chép lại.
    private static let preferredLanguageKey = "preferredLanguage"

    // MARK: - Lựa chọn trong app phải thắng ngôn ngữ hệ thống

    /// Đây là toàn bộ lý do tính năng này tồn tại: người đang chạy macOS tiếng
    /// Việt vẫn phải xem được Caffeinate bằng tiếng Anh.
    ///
    /// Tiến trình khởi chạy với `-AppleLanguages (vi)` — hệ thống nói tiếng
    /// Việt — nhưng `-preferredLanguage en` đặt sẵn lựa chọn trong app.
    func testInAppSelectionOverridesSystemLanguage() {
        let app = launch(systemLanguage: "vi", locale: "vi_VN", preferred: "en")

        XCTAssertTrue(app.buttons["Turn on indefinitely"].firstMatch.waitForExistence(timeout: 10),
                      "Hệ thống tiếng Việt + lựa chọn tiếng Anh phải ra giao diện tiếng Anh")
        XCTAssertFalse(app.buttons["Bật không giới hạn"].firstMatch.exists,
                       "Không được còn sót nhãn tiếng Việt nào")

        app.terminate()
    }

    /// Chiều ngược lại, để chắc rằng test trên không ăn may vì máy chạy test
    /// tình cờ đang đặt tiếng Anh.
    func testInAppSelectionCanForceVietnameseOnAnEnglishSystem() {
        let app = launch(systemLanguage: "en", locale: "en_US", preferred: "vi")

        XCTAssertTrue(app.buttons["Bật không giới hạn"].firstMatch.waitForExistence(timeout: 10),
                      "Hệ thống tiếng Anh + lựa chọn tiếng Việt phải ra giao diện tiếng Việt")
        XCTAssertFalse(app.buttons["Turn on indefinitely"].firstMatch.exists)

        app.terminate()
    }

    private func launch(systemLanguage: String, locale: String, preferred: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            Self.uiTestingArgument,
            "-AppleLanguages", "(\(systemLanguage))",
            "-AppleLocale", locale,
            "-\(Self.preferredLanguageKey)", preferred,
        ]
        app.launch()
        return app
    }

    // MARK: - Không chuỗi nào được quên dịch

    /// Đối chiếu bảng chuỗi tiếng Việt với bảng tiếng Anh, cả hai đọc thẳng từ
    /// app bundle đã biên dịch.
    ///
    /// Cách kiểm tra này được chọn sau khi cách hiển nhiên hơn tỏ ra vô dụng:
    /// thoạt tiên test đi tìm những khoá mà bản tiếng Anh TRÙNG bản gốc, giả
    /// định rằng khoá chưa dịch sẽ ánh xạ về chính nó. Thử gỡ hẳn một bản dịch
    /// ra rồi chạy lại thì test vẫn xanh — trình biên dịch String Catalog đơn
    /// giản là KHÔNG ghi khoá đó vào `en.lproj` chút nào. Một test không bao
    /// giờ đỏ được thì không bảo vệ được gì.
    ///
    /// Tiếng Việt là ngôn ngữ gốc nên bảng của nó chứa đủ mọi khoá; thứ vắng
    /// mặt bên tiếng Anh đúng là thứ chưa ai dịch.
    func testEveryStringHasAnEnglishTranslation() throws {
        let vietnamese = try keys(forLanguage: "vi")
        let english = try keys(forLanguage: "en")

        XCTAssertGreaterThan(vietnamese.count, 50, "Không đọc được bảng chuỗi tiếng Việt")

        let missing = vietnamese.subtracting(english).sorted()
        XCTAssertTrue(
            missing.isEmpty,
            "Những khoá sau chưa có bản dịch tiếng Anh: \(missing)"
        )
    }

    /// Mọi chuỗi VIẾT TRONG MÃ phải có mặt trong String Catalog.
    ///
    /// Đây là lỗ hổng mà `testEveryStringHasAnEnglishTranslation` không bịt
    /// được, và là lỗi dễ mắc hơn hẳn: thêm một `Text("…")` mới rồi quên khai
    /// báo trong catalog. Khi đó build KHÔNG cảnh báo gì (đã kiểm chứng), khoá
    /// không xuất hiện trong bảng chuỗi của bất kỳ ngôn ngữ nào, và SwiftUI
    /// lặng lẽ hiển thị chính chuỗi tiếng Việt viết trong mã — kể cả cho người
    /// dùng đang đọc tiếng Anh.
    ///
    /// Trình biên dịch có ghi lại danh sách chuỗi nó trích xuất được, kèm cả
    /// vị trí trong mã, vào các file `.stringsdata` ở thư mục build trung gian.
    /// Đối chiếu danh sách đó với bảng tiếng Việt (ngôn ngữ gốc, chứa mọi khoá
    /// mà catalog biết) là đủ để bắt.
    func testEveryStringInCodeIsDeclaredInTheCatalog() throws {
        let inCode = try keysExtractedFromSource()
        let inCatalog = try keys(forLanguage: "vi")

        XCTAssertFalse(inCode.isEmpty, "Không đọc được dữ liệu trích xuất chuỗi")

        let undeclared = inCode.subtracting(inCatalog).sorted()
        XCTAssertTrue(
            undeclared.isEmpty,
            "Những chuỗi sau có trong mã nhưng chưa khai báo trong Localizable.xcstrings: \(undeclared)"
        )
    }

    /// Đọc `*.stringsdata` mà trình biên dịch sinh ra cho app target.
    ///
    /// Bỏ qua file nào trỏ tới một file nguồn đã không còn: build trung gian
    /// không tự dọn, nên dữ liệu của một file đã xoá hoặc đổi tên vẫn nằm lại
    /// và sẽ báo nhầm về những chuỗi không còn ai dùng.
    private func keysExtractedFromSource() throws -> Set<String> {
        let build = try appBundle()               // …/Build/Products/<config>/Caffeinate.app
            .deletingLastPathComponent()          // …/Build/Products/<config>
            .deletingLastPathComponent()          // …/Build/Products
            .deletingLastPathComponent()          // …/Build
            .appendingPathComponent("Intermediates.noindex/Caffeinate.build")

        guard let walker = FileManager.default.enumerator(
            at: build, includingPropertiesForKeys: nil
        ) else {
            throw XCTSkip("Không tìm thấy thư mục build trung gian")
        }

        var keys = Set<String>()
        for case let url as URL in walker where url.pathExtension == "stringsdata" {
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let source = root["source"] as? String,
                  FileManager.default.fileExists(atPath: source),
                  let tables = root["tables"] as? [String: Any],
                  let localizable = tables["Localizable"] as? [[String: Any]]
            else { continue }

            keys.formUnion(localizable.compactMap { $0["key"] as? String })
        }
        return keys
    }

    /// Gom khoá từ cả `.strings` lẫn `.stringsdict`: chuỗi có dạng số nhiều nằm
    /// ở file thứ hai, nên chỉ đọc file thứ nhất sẽ báo nhầm là thiếu.
    private func keys(forLanguage language: String) throws -> Set<String> {
        let resources = try appBundle()
            .appendingPathComponent("Contents/Resources/\(language).lproj")

        var all = Set<String>()
        for name in ["Localizable.strings", "Localizable.stringsdict"] {
            guard let data = try? Data(contentsOf: resources.appendingPathComponent(name)) else {
                continue
            }
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
            if let table = plist as? [String: Any] {
                all.formUnion(table.keys)
            }
        }
        return all
    }

    /// Tìm ngược lên từ bundle của chính test cho tới thư mục sản phẩm chứa
    /// `Caffeinate.app`. Không cắm cứng số cấp thư mục: `.xctest` nằm lồng
    /// trong `…-Runner.app/Contents/PlugIns/`, và độ sâu đó là chi tiết của
    /// Xcode chứ không phải thứ đáng để test phụ thuộc vào.
    private func appBundle() throws -> URL {
        var directory = Bundle(for: type(of: self)).bundleURL

        for _ in 0..<8 {
            directory = directory.deletingLastPathComponent()
            let candidate = directory.appendingPathComponent("Caffeinate.app")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw XCTSkip("Không tìm thấy Caffeinate.app cạnh bundle test")
    }
}
