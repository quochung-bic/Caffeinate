import Foundation
import Observation
import SwiftUI

/// Ngôn ngữ giao diện mà người dùng chọn.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    /// Theo ngôn ngữ hệ thống. Đây là mặc định, và nên là mặc định: người dùng
    /// đã nói cho macOS biết họ đọc tiếng gì rồi, hỏi lại là thừa.
    case system
    case vietnamese = "vi"
    case english = "en"

    var id: String { rawValue }

    /// `nil` nghĩa là không ép — cứ để hệ thống quyết.
    var localeIdentifier: String? {
        self == .system ? nil : rawValue
    }
}

/// Lựa chọn ngôn ngữ, lưu lại và áp dụng NGAY, không cần khởi động lại app.
///
/// # Vì sao làm được ngay
///
/// SwiftUI tra chuỗi theo `EnvironmentValues.locale`, nên chỉ cần bơm locale
/// vào gốc mỗi scene là toàn bộ `Text("…")` đổi theo tức thì. Đã đo: ép
/// `.environment(\.locale, "en")` trong khi tiến trình chạy tiếng Việt thì nhãn
/// nút ra tiếng Anh.
///
/// # Cái bẫy ở đây
///
/// `String(localized:locale:)` KHÔNG dùng tham số `locale` để chọn bảng chuỗi —
/// nó chỉ dùng để chọn luật số nhiều, còn bảng thì vẫn lấy theo ngôn ngữ của
/// tiến trình. Đã đo: gọi với `locale: "vi"` trên máy chạy tiếng Anh vẫn trả về
/// "Stop". Dùng nó cho phần chuyển ngữ sẽ ra một app đổi được nút nhưng không
/// đổi được thông báo, và tệ hơn là ghép luật số nhiều tiếng Việt vào câu tiếng
/// Anh ("1 minutes left").
///
/// Cách đúng cho các chuỗi ngoài SwiftUI là `LocalizedStringResource` có gán
/// `locale` — cái đó chọn bảng thật. Xem `resolve(_:)` và `LocalizedStringResource.text(in:)`.
@MainActor
@Observable
final class LanguagePreference {
    /// Khoá trong UserDefaults. UI test đặt sẵn được bằng `-preferredLanguage en`
    /// vì miền đối số của NSUserDefaults tự nhận cú pháp `-khoá giá trị`.
    static let defaultsKey = "preferredLanguage"

    private let defaults: UserDefaults

    var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            persist()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.defaultsKey) ?? ""
        self.selection = AppLanguage(rawValue: stored) ?? .system
    }

    /// Locale để bơm vào `\.locale` của mỗi scene.
    var locale: Locale {
        guard let identifier = selection.localeIdentifier else {
            // `autoupdatingCurrent` chứ không phải `current`: người dùng đổi
            // ngôn ngữ hệ thống trong lúc app đang chạy thì app đi theo.
            return .autoupdatingCurrent
        }
        return Locale(identifier: identifier)
    }

    /// Dựng chuỗi cho phần KHÔNG phải SwiftUI (thông báo, nhãn VoiceOver của
    /// icon menu bar) — nơi không có environment để dựa vào.
    func resolve(_ resource: LocalizedStringResource) -> String {
        var localized = resource
        localized.locale = locale
        return String(localized: localized)
    }

    /// Ghi lựa chọn xuống đĩa, và đồng thời ghi `AppleLanguages` vào miền
    /// UserDefaults của chính app.
    ///
    /// Hai việc chứ không phải một, vì chúng lo hai phần khác nhau: `\.locale`
    /// đổi ngay giao diện DO APP VẼ, còn `AppleLanguages` đổi giao diện DO HỆ
    /// ĐIỀU HÀNH vẽ hộ — hộp thoại chọn app, hộp xin quyền thông báo, tên app
    /// trong Login Items. Phần sau chỉ có hiệu lực từ lần mở app kế tiếp, vì
    /// bundle nạp danh sách ngôn ngữ đúng một lần lúc khởi động. Giao diện phải
    /// nói rõ điều đó thay vì để người dùng tự phát hiện.
    ///
    /// Đây cũng chính là cơ chế mà System Settings › General › Language & Region
    /// › Applications dùng, nên hai nơi không đánh nhau.
    private func persist() {
        if let identifier = selection.localeIdentifier {
            defaults.set(selection.rawValue, forKey: Self.defaultsKey)
            defaults.set([identifier], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: Self.defaultsKey)
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }
}

extension LocalizedStringResource {
    /// Dựng `Text` cho một tài nguyên chuỗi theo đúng locale đang chọn.
    ///
    /// Cần thiết vì `Text(resource)` bám theo locale GẮN TRONG tài nguyên chứ
    /// không đọc environment — khác với `Text("chuỗi literal")`. Không gán thì
    /// literal đổi ngôn ngữ còn những chuỗi đến từ `CaffeinateKit` thì không,
    /// và giao diện ra nửa nọ nửa kia.
    func text(in locale: Locale) -> Text {
        var localized = self
        localized.locale = locale
        return Text(localized)
    }
}
