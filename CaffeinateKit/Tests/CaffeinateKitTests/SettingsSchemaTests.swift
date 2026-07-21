import Foundation
import Testing
@testable import CaffeinateKit

/// Cài đặt là dữ liệu của người dùng và sống lâu hơn mọi phiên bản app.
/// Bộ test này giữ lời hứa: nâng cấp, hạ cấp, hay một file plist bị sửa tay
/// đều KHÔNG được làm mất cấu hình.
@Suite("Settings schema")
struct SettingsSchemaTests {

    private func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    @Test("thiếu khoá thì lấy mặc định cho riêng khoá đó, không vứt cả bộ")
    func missingKeysFallBackIndividually() throws {
        // Đây chính là hình dạng dữ liệu do một bản app CŨ ghi ra: chưa có
        // externalDisplayTriggerEnabled, chưa có activateOnLaunch. Codable
        // sinh tự động sẽ ném lỗi ở đây, và store bắt lỗi bằng cách trả về
        // Settings() — tức là xoá sạch cấu hình của người dùng.
        // `AssertionFlags` mã hoá qua RawRepresentable nên trên đĩa nó là một
        // số nguyên trần, không phải object bọc rawValue.
        let settings = try decode(#"{"flags":3,"customDurationMinutes":90}"#)

        #expect(settings.flags == [.system, .display])
        #expect(settings.customDurationMinutes == 90)
        #expect(settings.externalDisplayTriggerEnabled == false)
        #expect(settings.activateOnLaunch == false)
    }

    @Test("JSON rỗng vẫn cho ra bộ mặc định hợp lệ")
    func emptyObjectDecodes() throws {
        #expect(try decode("{}") == Settings())
    }

    @Test("khoá lạ từ bản app mới hơn bị bỏ qua, không làm hỏng phần đọc được")
    func unknownKeysAreIgnored() throws {
        let settings = try decode(#"{"customDurationMinutes":60,"quantumFoamMode":true}"#)
        #expect(settings.customDurationMinutes == 60)
    }

    @Test("thời lượng ngoài khoảng bị kẹp về biên, kể cả khi tới từ file sửa tay")
    func durationIsClampedOnDecode() throws {
        #expect(try decode(#"{"customDurationMinutes":100000}"#).customDurationMinutes == 480)
        #expect(try decode(#"{"customDurationMinutes":-7}"#).customDurationMinutes == 1)
        #expect(try decode(#"{"customDurationMinutes":0}"#).customDurationMinutes == 1)
    }

    @Test("bundle ID trùng hoặc rỗng bị loại, thứ tự người dùng thêm được giữ")
    func bundleIDsAreDeduplicatedInOrder() throws {
        let settings = try decode(
            #"{"triggerAppBundleIDs":["b","a","b","","a","c"]}"#
        )
        #expect(settings.triggerAppBundleIDs == ["b", "a", "c"])
    }

    @Test("bản ghi ra luôn kèm số hiệu schema để sau này còn chỗ bám mà migrate")
    func encodesSchemaVersion() throws {
        let data = try JSONEncoder().encode(Settings())
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["schemaVersion"] as? Int == Settings.currentSchemaVersion)
    }

    @Test("ghi rồi đọc lại là phép đồng nhất")
    func roundTripsThroughJSON() throws {
        var settings = Settings()
        settings.flags = [.system, .disk, .userIdle]
        settings.customDurationMinutes = 120
        settings.triggerAppBundleIDs = ["com.apple.dt.Xcode"]
        settings.appTriggerEnabled = true
        settings.activateOnLaunch = true

        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(Settings.self, from: data) == settings)
    }

    @Test("store cũng chuẩn hoá lúc GHI, không chỉ lúc đọc")
    func storeNormalizesOnWrite() throws {
        let suiteName = "test.caffeinate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSettingsStore(defaults: defaults)
        var settings = Settings()
        settings.customDurationMinutes = 9_999
        settings.triggerAppBundleIDs = ["a", "a"]
        store.settings = settings

        #expect(store.settings.customDurationMinutes == 480)
        #expect(store.settings.triggerAppBundleIDs == ["a"])
    }
}
