import Foundation
import Observation
import ServiceManagement

/// Bọc `SMAppService`.
///
/// Không soi gương trạng thái vào UserDefaults: `SMAppService.mainApp.status`
/// là nguồn sự thật duy nhất. Người dùng có thể tắt login item từ System
/// Settings > General > Login Items mà app không hề hay biết — giữ một bản sao
/// nghĩa là sớm muộn cũng hiển thị sai.
@MainActor
@Observable
final class LaunchAtLogin {
    /// Tài nguyên chuỗi, không phải `String` đã dựng: chỉ tầng view mới biết
    /// người dùng đang chọn ngôn ngữ nào, và câu lỗi phải đổi theo cùng lúc với
    /// phần còn lại của cửa sổ.
    private(set) var lastError: LocalizedStringResource?

    /// Đọc thẳng từ hệ thống mỗi lần, không cache.
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = Self.explain(error, whileEnabling: enabled)
        }
    }

    /// Nguyên nhân hay gặp nhất không phải là "hệ thống trục trặc" mà là app
    /// đang chạy ngoài /Applications — `SMAppService` từ chối đăng ký những
    /// bundle nằm ở chỗ khác. Nói thẳng ra điều đó, vì người dùng sửa được;
    /// còn "thao tác thất bại" thì họ không làm gì được.
    private static func explain(_ error: any Error, whileEnabling enabling: Bool) -> LocalizedStringResource {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasPrefix("/Applications") else {
            return """
                Không đổi được cài đặt khởi động: app phải nằm trong thư mục \
                /Applications. Hiện tại đang chạy từ \(bundlePath).
                """
        }
        return enabling
            ? "Không bật được khởi động cùng macOS: \(error.localizedDescription)"
            : "Không tắt được khởi động cùng macOS: \(error.localizedDescription)"
    }
}
