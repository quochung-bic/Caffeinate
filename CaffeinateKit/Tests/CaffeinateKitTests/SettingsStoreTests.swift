import Foundation
import Testing
@testable import CaffeinateKit

@Suite("SettingsStore")
struct SettingsStoreTests {

    private func makeStore() -> (UserDefaultsSettingsStore, UserDefaults, String) {
        let suiteName = "test.caffeinate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (UserDefaultsSettingsStore(defaults: defaults), defaults, suiteName)
    }

    @Test("store rỗng trả về giá trị mặc định an toàn")
    func returnsDefaultsWhenEmpty() {
        let (store, defaults, suiteName) = makeStore()

        #expect(store.settings == Settings())
        #expect(store.settings.flags == .default)
        #expect(store.settings.customDurationMinutes == 45)
        #expect(store.settings.triggerAppBundleIDs.isEmpty)
        #expect(store.settings.activateOnLaunch == false)

        // Cleanup: remove persistent domain to avoid accumulating orphaned preferences
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("ghi rồi đọc lại giữ nguyên giá trị")
    func roundTrips() {
        let (store, defaults, suiteName) = makeStore()

        var settings = Settings()
        settings.flags = [.system, .disk, .userIdle]
        settings.customDurationMinutes = 90
        settings.triggerAppBundleIDs = ["com.apple.dt.Xcode", "com.docker.docker"]
        settings.chargingTriggerEnabled = true
        settings.activateOnLaunch = true
        store.settings = settings

        // Flush to disk to ensure data reaches the persistent backing store
        defaults.synchronize()

        // Đọc bằng instance mới trên cùng suite name để chắc chắn đã ghi xuống đĩa.
        // Tạo UserDefaults object tập tươi để loại trừ in-memory cache của object cũ.
        let freshDefaults = UserDefaults(suiteName: suiteName)!
        let reloaded = UserDefaultsSettingsStore(defaults: freshDefaults)
        #expect(reloaded.settings == settings)

        // Cleanup: remove persistent domain to avoid accumulating orphaned preferences
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("dữ liệu hỏng thì rơi về mặc định thay vì crash")
    func corruptDataFallsBackToDefaults() {
        let (store, defaults, suiteName) = makeStore()
        defaults.set(Data("không phải json".utf8), forKey: "settings")

        #expect(store.settings == Settings())

        // Cleanup: remove persistent domain to avoid accumulating orphaned preferences
        defaults.removePersistentDomain(forName: suiteName)
    }
}
