import AppKit
import Observation
import UserNotifications

/// Báo cho người dùng biết hẹn giờ đã hết bằng ba đường độc lập, vì mỗi đường
/// đều có lúc câm: banner bị Do Not Disturb chặn hoặc người dùng từ chối quyền,
/// âm thanh vô nghĩa khi đang đeo tai nghe ở phòng khác, icon nhấp nháy chỉ
/// thấy nếu đang nhìn lên thanh menu.
///
/// Banner cố tình KHÔNG kèm âm thanh: âm thanh do đây tự phát, nên dù banner có
/// bị chặn hay không thì cũng đúng một tiếng chuông, không bao giờ hai.
@MainActor
@Observable
final class TimerExpiryAlert {
    /// Bật/tắt liên tục trong lúc nhấp nháy; nhãn menu bar đọc để đổi icon.
    private(set) var isFlashing = false

    @ObservationIgnored private var flashTask: Task<Void, Never>?
    /// Tăng mỗi lần bắt đầu một lượt nhấp nháy mới. Một Task đã bị bỏ không
    /// được phép dọn dẹp thay cho lượt kế tiếp — nếu không, lượt cũ sẽ tắt cờ
    /// `isFlashing` mà lượt mới vừa bật, và xoá luôn tham chiếu tới Task mới
    /// khiến `cancelFlashing()` sau đó không huỷ được gì.
    @ObservationIgnored private var flashGeneration = 0
    @ObservationIgnored private var authorizationRequested = false
    @ObservationIgnored private let presenter = ForegroundPresenter()

    /// Số nhịp nhấp nháy. Không nhấp nháy vô hạn: một cái icon chớp mãi trên
    /// thanh menu là phiền, mà thông tin thì đã truyền đạt xong từ lâu.
    private static let flashCount = 6
    private static let flashInterval = Duration.milliseconds(280)

    /// Xin quyền thông báo lúc người dùng bắt đầu lần hẹn giờ ĐẦU TIÊN, không
    /// phải lúc khởi động: hỏi ngay khi người dùng vừa làm đúng cái việc sẽ dẫn
    /// tới thông báo thì họ còn hiểu vì sao mình được hỏi. Hỏi lúc hết giờ thì
    /// quá muộn — hộp thoại xin quyền hiện ra thay cho chính thông báo đó.
    func prepareForTimer() {
        guard !authorizationRequested else { return }
        authorizationRequested = true

        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        center.requestAuthorization(options: [.alert]) { _, error in
            if let error {
                // Không nuốt lỗi: không có banner thì vẫn còn âm thanh và icon
                // nhấp nháy, nhưng phải thấy được lý do khi soi log.
                NSLog("Caffeinate: xin quyền thông báo thất bại: %@", error.localizedDescription)
            }
        }
    }

    /// `stillActive` = hết giờ nhưng một luật tự động vẫn đang giữ máy thức.
    /// Nói đúng chuyện đang xảy ra thay vì báo cứng "máy sắp ngủ".
    /// `language` phải truyền vào chứ không đọc từ đâu đó: thông báo được gửi
    /// ngoài mọi view nên không có `\.locale` của environment để dựa vào, và
    /// nếu lấy ngôn ngữ tiến trình thì banner sẽ nói một thứ tiếng còn giao
    /// diện nói một thứ tiếng khác.
    func fire(stillActive: Bool, language: LanguagePreference) {
        playSound()
        startFlashing()
        postNotification(stillActive: stillActive, language: language)
    }

    func cancelFlashing() {
        flashTask?.cancel()
        flashTask = nil
        flashGeneration += 1
        isFlashing = false
    }

    private func playSound() {
        NSSound(named: "Glass")?.play()
    }

    private func startFlashing() {
        flashTask?.cancel()
        flashGeneration += 1
        let generation = flashGeneration

        flashTask = Task { [weak self] in
            for _ in 0..<Self.flashCount {
                guard !Task.isCancelled else { return }
                self?.isFlashing = true
                try? await Task.sleep(for: Self.flashInterval)
                guard !Task.isCancelled else { return }
                self?.isFlashing = false
                try? await Task.sleep(for: Self.flashInterval)
            }
            // Chỉ dọn nếu mình vẫn là lượt hiện hành.
            guard let self, self.flashGeneration == generation else { return }
            self.isFlashing = false
            self.flashTask = nil
        }
    }

    private func postNotification(stillActive: Bool, language: LanguagePreference) {
        let content = UNMutableNotificationContent()
        content.title = language.resolve("Hết giờ")
        content.body = language.resolve(
            stillActive
                ? "Hẹn giờ đã xong, nhưng một luật tự động vẫn đang giữ máy thức."
                : "Caffeinate đã tắt. Máy có thể ngủ như bình thường."
        )

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Caffeinate: gửi thông báo thất bại: %@", error.localizedDescription)
            }
        }
    }
}

/// Mặc định macOS nuốt banner khi app đang ở tiền cảnh — hợp lý với app có cửa
/// sổ, sai với app này: cửa sổ Cài đặt đang mở không có nghĩa là người dùng
/// đang nhìn nó, và cũng chẳng có chỗ nào trong đó báo hết giờ.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Không kèm .sound: tiếng chuông do TimerExpiryAlert tự phát, để dù
        // banner có bị chặn cũng đúng một tiếng.
        [.banner, .list]
    }
}
