import Foundation

/// Cấu hình người dùng chỉnh được.
///
/// Không chứa launch-at-login — `SMAppService.mainApp.status` là nguồn sự thật
/// cho việc đó, và soi gương nó vào đây chỉ tạo ra hai sự thật lệch nhau khi
/// người dùng tắt login item từ System Settings.
public struct Settings: Equatable, Sendable {

    /// Khoảng hợp lệ của thời lượng tuỳ chỉnh. Sống ở đây chứ không phải trong
    /// UI: đây là bất biến của dữ liệu, phải đúng kể cả khi giá trị tới từ một
    /// file plist người dùng sửa tay chứ không qua Stepper.
    public static let durationRange = 1...480

    public var flags: AssertionFlags = .default
    public var customDurationMinutes: Int = 45
    public var triggerAppBundleIDs: [String] = []
    public var appTriggerEnabled: Bool = false
    public var chargingTriggerEnabled: Bool = false
    public var externalDisplayTriggerEnabled: Bool = false
    /// Bật sẵn ngay khi app khởi chạy. Chỉ có tác dụng thực tế nếu
    /// launch-at-login đang bật — UI phải nói rõ điều này.
    public var activateOnLaunch: Bool = false

    public init() {}

    /// Ép mọi trường về khoảng hợp lệ. Gọi ở biên đọc/ghi, nên không giá trị
    /// hỏng nào lọt được vào phần còn lại của app.
    public mutating func normalize() {
        customDurationMinutes = min(
            max(customDurationMinutes, Self.durationRange.lowerBound),
            Self.durationRange.upperBound
        )
        // Bỏ trùng nhưng GIỮ NGUYÊN thứ tự người dùng đã thêm.
        var seen = Set<String>()
        triggerAppBundleIDs = triggerAppBundleIDs.filter {
            !$0.isEmpty && seen.insert($0).inserted
        }
    }
}

// MARK: - Codable

/// Giải mã khoan dung có chủ đích.
///
/// Cài đặt là dữ liệu của NGƯỜI DÙNG, tồn tại lâu hơn bất kỳ phiên bản app nào.
/// Nếu thêm một trường mới mà bản cũ chưa có, hoặc người dùng hạ cấp app, thì
/// `Codable` sinh tự động sẽ ném lỗi và — theo cách store bắt lỗi bên dưới —
/// xoá sạch toàn bộ cấu hình. Mất hết chỉ vì thiếu một khoá là hành vi không
/// thể chấp nhận.
///
/// Vậy nên mỗi trường được đọc độc lập bằng `decodeIfPresent`, thiếu thì lấy
/// mặc định. Cộng với `schemaVersion` để sau này có chỗ bám khi cần migrate
/// thật sự (đổi ý nghĩa một trường, chứ không phải thêm trường).
extension Settings: Codable {
    /// Tăng khi ý nghĩa của một trường ĐÃ CÓ thay đổi. Thêm trường mới thì
    /// không cần tăng — phần đọc khoan dung ở dưới đã lo.
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
                // Dữ liệu hỏng hoặc chưa có: mặc định an toàn, không crash.
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
