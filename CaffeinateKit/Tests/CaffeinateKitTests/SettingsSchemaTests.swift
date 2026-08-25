import Foundation
import Testing
@testable import CaffeinateKit

/// Settings are the user's data and outlive every version of the app.
/// This suite holds that promise: an upgrade, a downgrade, or a hand-edited
/// plist must NEVER lose the configuration.
@Suite("Settings schema")
struct SettingsSchemaTests {

    private func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    @Test("a missing key falls back for that key alone, not for the whole set")
    func missingKeysFallBackIndividually() throws {
        // This is exactly the shape an OLD build would have written: no
        // externalDisplayTriggerEnabled, no activateOnLaunch. The synthesized
        // Codable would throw here, and the store catches that by returning
        // Settings() — which wipes the user's configuration.
        // `AssertionFlags` encodes through RawRepresentable, so on disk it is a
        // bare integer rather than an object wrapping rawValue.
        let settings = try decode(#"{"flags":3,"customDurationMinutes":90}"#)

        #expect(settings.flags == [.system, .display])
        #expect(settings.customDurationMinutes == 90)
        #expect(settings.externalDisplayTriggerEnabled == false)
        #expect(settings.activateOnLaunch == false)
    }

    @Test("empty JSON still decodes to a valid default set")
    func emptyObjectDecodes() throws {
        #expect(try decode("{}") == Settings())
    }

    @Test("unknown keys from a newer build are ignored without breaking the rest")
    func unknownKeysAreIgnored() throws {
        let settings = try decode(#"{"customDurationMinutes":60,"quantumFoamMode":true}"#)
        #expect(settings.customDurationMinutes == 60)
    }

    @Test("out-of-range durations are clamped, even from a hand-edited file")
    func durationIsClampedOnDecode() throws {
        #expect(try decode(#"{"customDurationMinutes":100000}"#).customDurationMinutes == 480)
        #expect(try decode(#"{"customDurationMinutes":-7}"#).customDurationMinutes == 1)
        #expect(try decode(#"{"customDurationMinutes":0}"#).customDurationMinutes == 1)
    }

    @Test("duplicate and empty bundle IDs are dropped, preserving the user's order")
    func bundleIDsAreDeduplicatedInOrder() throws {
        let settings = try decode(
            #"{"triggerAppBundleIDs":["b","a","b","","a","c"]}"#
        )
        #expect(settings.triggerAppBundleIDs == ["b", "a", "c"])
    }

    @Test("what is written always carries a schema version for a future migration")
    func encodesSchemaVersion() throws {
        let data = try JSONEncoder().encode(Settings())
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["schemaVersion"] as? Int == Settings.currentSchemaVersion)
    }

    @Test("writing then reading back is the identity")
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

    @Test("the store normalizes on WRITE too, not only on read")
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
