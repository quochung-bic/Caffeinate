import AppKit
import Testing
@testable import CaffeinateKit

@Suite("MenuBarIcon")
@MainActor
struct MenuBarIconTests {

    @Test("icon luôn là template image để thích ứng sáng/tối")
    func isTemplateImage() {
        let image = MenuBarIcon.image(for: MenuBarIconState(
            isActive: true, progress: 0.5, hasError: false
        ))
        #expect(image.isTemplate)
    }

    @Test("icon đúng kích thước menu bar")
    func hasMenuBarSize() {
        let image = MenuBarIcon.image(for: MenuBarIconState(
            isActive: false, progress: nil, hasError: false
        ))
        #expect(image.size == NSSize(width: 18, height: 18))
    }

    @Test("mô tả trợ năng do người gọi truyền vào, không do package tự đặt")
    func accessibilityDescriptionComesFromCaller() {
        // Package không được chứa chuỗi giao diện: nó không biết người dùng
        // đang dùng ngôn ngữ nào. Tầng app tra String Catalog rồi đưa xuống.
        let image = MenuBarIcon.image(
            for: .init(isActive: true, progress: nil, hasError: false),
            accessibilityDescription: "any caller string"
        )
        #expect(image.accessibilityDescription == "any caller string")
    }

    @Test("trạng thái lỗi vẫn nhận được mô tả trợ năng của người gọi")
    func errorStateKeepsCallerDescription() {
        let image = MenuBarIcon.image(
            for: .init(isActive: true, progress: 0.5, hasError: true),
            accessibilityDescription: "error text"
        )
        #expect(image.accessibilityDescription == "error text")
        #expect(image.isTemplate)
    }

    @Test("trạng thái khác nhau cho ra hình khác nhau")
    func distinctStatesRenderDifferently() throws {
        let off = try #require(MenuBarIcon.image(for:
            .init(isActive: false, progress: nil, hasError: false)).tiffRepresentation)
        let on = try #require(MenuBarIcon.image(for:
            .init(isActive: true, progress: nil, hasError: false)).tiffRepresentation)
        let quarter = try #require(MenuBarIcon.image(for:
            .init(isActive: true, progress: 0.25, hasError: false)).tiffRepresentation)
        let threeQuarter = try #require(MenuBarIcon.image(for:
            .init(isActive: true, progress: 0.75, hasError: false)).tiffRepresentation)

        #expect(off != on)
        #expect(quarter != threeQuarter)
        #expect(on != quarter)
    }

    @Test("progress ngoài khoảng 0...1 bị kẹp lại thay vì vẽ sai")
    func clampsOutOfRangeProgress() throws {
        #expect(MenuBarIconState(isActive: true, progress: 1.8, hasError: false).progress == 1.0)
        #expect(MenuBarIconState(isActive: true, progress: -0.5, hasError: false).progress == 0.0)

        let over = try #require(MenuBarIcon.image(for:
            .init(isActive: true, progress: 1.8, hasError: false)).tiffRepresentation)
        let full = try #require(MenuBarIcon.image(for:
            .init(isActive: true, progress: 1.0, hasError: false)).tiffRepresentation)
        #expect(over == full)
    }

    // MARK: - Lượng tử hoá & cache

    @Test("progress được làm tròn về bậc, nên hai giá trị sát nhau là MỘT trạng thái")
    func quantizesProgressIntoSteps() {
        // 1/32 = 0.03125. Hai giá trị cách nhau chưa tới nửa bậc phải gộp lại,
        // nếu không cache sẽ trượt mỗi giây và mất sạch tác dụng.
        let a = MenuBarIconState(isActive: true, progress: 0.500, hasError: false)
        let b = MenuBarIconState(isActive: true, progress: 0.505, hasError: false)
        #expect(a == b)
        #expect(a.progress == 0.5)

        // Còn cách nhau trọn một bậc thì vẫn phải phân biệt được.
        let c = MenuBarIconState(isActive: true, progress: 0.5 + 1 / 32.0, hasError: false)
        #expect(a != c)
    }

    @Test("cùng một trạng thái trả về đúng một đối tượng ảnh, không dựng lại")
    func cacheReturnsIdenticalInstance() {
        let state = MenuBarIconState(isActive: true, progress: 0.25, hasError: false)
        let first = MenuBarIcon.cachedImage(for: state, accessibilityDescription: "a")
        let second = MenuBarIcon.cachedImage(for: state, accessibilityDescription: "a")
        #expect(first === second)
    }

    @Test("cache dùng lại ảnh nhưng mô tả trợ năng vẫn cập nhật theo từng giây")
    func cacheStillRefreshesAccessibilityDescription() {
        // Hình không đổi khi còn 12 phút hay 11 phút, nhưng câu đọc cho
        // VoiceOver thì đổi — nên mô tả không được nằm trong khoá cache.
        let state = MenuBarIconState(isActive: true, progress: 0.75, hasError: false)
        _ = MenuBarIcon.cachedImage(for: state, accessibilityDescription: "còn 12 phút")
        let again = MenuBarIcon.cachedImage(for: state, accessibilityDescription: "còn 11 phút")
        #expect(again.accessibilityDescription == "còn 11 phút")
    }

    @Test("ảnh trống giữ nguyên kích thước để icon bên cạnh không nhảy khi nhấp nháy")
    func blankImageKeepsSize() {
        let blank = MenuBarIcon.blankImage()
        #expect(blank.size == MenuBarIcon.size)
        #expect(blank.isTemplate)
    }
}
