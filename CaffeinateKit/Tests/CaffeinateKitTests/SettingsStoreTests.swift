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

    @Test("an empty store returns safe defaults")
    func returnsDefaultsWhenEmpty() {
        let (store, defaults, suiteName) = makeStore()

        #expect(store.settings == Settings())
        #expect(store.settings.flags == .default)
        #expect(store.settings.customDurationMinutes == 45)
        #expect(store.settings.triggerAppBundleIDs.isEmpty)
        #expect(store.settings.activateOnLaunch == false)

        // Remove the persistent domain so orphaned preferences do not pile up.
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("writing then reading back preserves the values")
    func roundTrips() {
        let (store, defaults, suiteName) = makeStore()

        var settings = Settings()
        settings.flags = [.system, .disk, .userIdle]
        settings.customDurationMinutes = 90
        settings.triggerAppBundleIDs = ["com.apple.dt.Xcode", "com.docker.docker"]
        settings.chargingTriggerEnabled = true
        settings.activateOnLaunch = true
        store.settings = settings

        // Flush to disk so the data reaches the persistent backing store.
        defaults.synchronize()

        // Read through a new instance on the same suite to prove it really was
        // written. A fresh UserDefaults object rules out the old one's
        // in-memory cache.
        let freshDefaults = UserDefaults(suiteName: suiteName)!
        let reloaded = UserDefaultsSettingsStore(defaults: freshDefaults)
        #expect(reloaded.settings == settings)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("corrupt data falls back to defaults instead of crashing")
    func corruptDataFallsBackToDefaults() {
        let (store, defaults, suiteName) = makeStore()
        defaults.set(Data("not json".utf8), forKey: "settings")

        #expect(store.settings == Settings())

        defaults.removePersistentDomain(forName: suiteName)
    }
}
