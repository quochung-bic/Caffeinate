import Foundation

/// The settings a user can change.
///
/// Launch-at-login is deliberately absent: `SMAppService.mainApp.status` is the
/// source of truth for that, and mirroring it here would only create two
/// truths that drift apart the moment the user disables the login item from
/// System Settings.
public struct Settings: Equatable, Sendable {

    /// Valid range for the custom duration. It lives here rather than in the
    /// UI because it is an invariant of the data: it must hold even when the
    /// value arrives from a hand-edited plist rather than from a Stepper.
    public static let durationRange = 1...480

    public var flags: AssertionFlags = .default
    public var customDurationMinutes: Int = 45
    public var triggerAppBundleIDs: [String] = []
    public var appTriggerEnabled: Bool = false
    public var chargingTriggerEnabled: Bool = false
    public var externalDisplayTriggerEnabled: Bool = false
    /// Turn on as soon as the app launches. Only useful in practice when
    /// launch-at-login is enabled — the UI has to say so.
    public var activateOnLaunch: Bool = false

    public init() {}

    /// Force every field into its valid range. Called at the read/write
    /// boundary, so no bad value reaches the rest of the app.
    public mutating func normalize() {
        customDurationMinutes = min(
            max(customDurationMinutes, Self.durationRange.lowerBound),
            Self.durationRange.upperBound
        )
        // Drop duplicates but PRESERVE the order the user added them in.
        var seen = Set<String>()
        triggerAppBundleIDs = triggerAppBundleIDs.filter {
            !$0.isEmpty && seen.insert($0).inserted
        }
    }
}

// MARK: - Codable

/// Deliberately lenient decoding.
///
/// Settings are the USER's data and outlive any version of the app. If a new
/// field is added that an older build never wrote, or the user downgrades, the
/// synthesized `Codable` would throw — and, given how the store catches errors
/// below, wipe the entire configuration. Losing everything over one missing key
/// is not acceptable behaviour.
///
/// So each field is read independently with `decodeIfPresent`, falling back to
/// its default. Plus a `schemaVersion` to give a real migration something to
/// hang off later (when a field changes meaning, not when one is added).
extension Settings: Codable {
    /// Bump when an EXISTING field changes meaning. Adding a new field needs
    /// no bump — the lenient decoding below already covers it.
    static let currentSchemaVersion = 1

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case flags
        case customDurationMinutes
        case triggerAppBundleIDs
        case appTriggerEnabled
        case chargingTriggerEnabled
        case externalDisplayTriggerEnabled
        case activateOnLaunch
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = Settings()

        settings.flags = try container.decodeIfPresent(AssertionFlags.self, forKey: .flags)
            ?? settings.flags
        settings.customDurationMinutes = try container.decodeIfPresent(Int.self, forKey: .customDurationMinutes)
            ?? settings.customDurationMinutes
        settings.triggerAppBundleIDs = try container.decodeIfPresent([String].self, forKey: .triggerAppBundleIDs)
            ?? settings.triggerAppBundleIDs
        settings.appTriggerEnabled = try container.decodeIfPresent(Bool.self, forKey: .appTriggerEnabled)
            ?? settings.appTriggerEnabled
        settings.chargingTriggerEnabled = try container.decodeIfPresent(Bool.self, forKey: .chargingTriggerEnabled)
            ?? settings.chargingTriggerEnabled
        settings.externalDisplayTriggerEnabled = try container.decodeIfPresent(Bool.self, forKey: .externalDisplayTriggerEnabled)
            ?? settings.externalDisplayTriggerEnabled
        settings.activateOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .activateOnLaunch)
            ?? settings.activateOnLaunch

        settings.normalize()
        self = settings
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(flags, forKey: .flags)
        try container.encode(customDurationMinutes, forKey: .customDurationMinutes)
        try container.encode(triggerAppBundleIDs, forKey: .triggerAppBundleIDs)
        try container.encode(appTriggerEnabled, forKey: .appTriggerEnabled)
        try container.encode(chargingTriggerEnabled, forKey: .chargingTriggerEnabled)
        try container.encode(externalDisplayTriggerEnabled, forKey: .externalDisplayTriggerEnabled)
        try container.encode(activateOnLaunch, forKey: .activateOnLaunch)
    }
}

// MARK: - Store

public protocol SettingsStoring: AnyObject {
    var settings: Settings { get set }
}

public final class UserDefaultsSettingsStore: SettingsStoring {
    private static let key = "settings"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var settings: Settings {
        get {
            guard let data = defaults.data(forKey: Self.key),
                  let decoded = try? JSONDecoder().decode(Settings.self, from: data)
            else {
                // Corrupt or absent: fall back to safe defaults, never crash.
                return Settings()
            }
            return decoded
        }
        set {
            var normalized = newValue
            normalized.normalize()
            guard let data = try? JSONEncoder().encode(normalized) else { return }
            defaults.set(data, forKey: Self.key)
        }
    }
}
