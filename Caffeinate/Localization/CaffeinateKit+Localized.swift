import Foundation
import CaffeinateKit

// Cầu nối giữa dữ liệu và câu chữ.
//
// `CaffeinateKit` cố ý không chứa một chuỗi giao diện nào: nó không biết người
// dùng đang đọc tiếng gì, và một package lõi thì không nên biết. File này là
// chỗ DUY NHẤT dịch các kiểu của package thành thứ đọc được — mọi bản dịch nằm
// trong Localizable.xcstrings, khoá là chính chuỗi tiếng Việt ở đây.

extension AssertionFlags {
    /// Tên hiển thị của một cờ đơn. Tổ hợp không có tên — nó không phải thứ
    /// người dùng nhìn thấy bao giờ.
    var localizedName: LocalizedStringResource {
        switch self {
        case .system:   "Hệ thống"
        case .display:  "Màn hình"
        case .disk:     "Đĩa"
        case .userIdle: "Idle"
        default:        Self.unreachableName(for: self)
        }
    }

    /// Một dòng giải thích cờ này thật sự giữ điều gì. Người dùng không có
    /// nghĩa vụ biết "user idle assertion" nghĩa là gì.
    var localizedExplanation: LocalizedStringResource {
        switch self {
        case .system:   "Máy không tự vào chế độ ngủ."
        case .display:  "Màn hình không tắt. Tốn pin — chỉ bật khi cần nhìn liên tục."
        case .disk:     "Ổ đĩa không ngủ."
        case .userIdle: "Máy không tính là bạn đang rảnh tay."
        default:        Self.unreachableName(for: self)
        }
    }

    /// Nhánh không thể tới: giao diện chỉ lặp qua `AssertionFlags.all`, toàn cờ
    /// đơn. Nếu tới được đây thì đó là lỗi lập trình, và một mã số nhìn thấy
    /// được vẫn hơn một ô trống không ai hiểu.
    ///
    /// Dựng qua `stringLiteral:` từ một chuỗi tính lúc chạy chứ không viết
    /// literal thẳng: literal sẽ bị trích xuất thành một khoá dịch, và trước
    /// đây nhánh này để `""` nên catalog phải mang theo một khoá RỖNG. Test
    /// `testEveryStringInCodeIsDeclaredInTheCatalog` bắt được đúng chỗ đó.
    private static func unreachableName(for flag: AssertionFlags) -> LocalizedStringResource {
        LocalizedStringResource(stringLiteral: "AssertionFlags(\(flag.rawValue))")
    }

    /// Bản đã dựng thành `String`, cần khi tên cờ được nhúng vào một câu khác.
    /// Phải nhận locale: `String(localized:)` trần sẽ lấy ngôn ngữ của tiến
    /// trình, nên tên cờ sẽ không đổi theo lựa chọn trong app.
    func localizedName(in locale: Locale) -> String {
        var resource = localizedName
        resource.locale = locale
        return String(localized: resource)
    }
}

extension TriggerReason {
    var localizedDescription: LocalizedStringResource {
        switch self {
        case .app(let name):    "\(name) đang chạy"
        case .charging:         "Đang cắm sạc"
        case .externalDisplay:  "Có màn hình ngoài"
        }
    }
}

extension ActiveReason {
    var localizedDescription: LocalizedStringResource {
        switch self {
        case .manual:           "Bật thủ công"
        case .timer:            "Hẹn giờ"
        case .trigger(let reason): reason.localizedDescription
        }
    }

    /// Biểu tượng đi kèm lý do. Bốn nguồn kích hoạt khác nhau thì nên nhìn ra
    /// khác nhau ngay, không phải đọc mới biết.
    var symbolName: String {
        switch self {
        case .manual:                       "hand.tap.fill"
        case .timer:                        "timer"
        case .trigger(.app):                "app.badge.checkmark"
        case .trigger(.charging):           "powerplug.fill"
        case .trigger(.externalDisplay):    "display.2"
        }
    }
}

extension AssertionFailure {
    /// Câu báo lỗi cho người dùng.
    ///
    /// Hai ca đầu cố tình nói rõ HẬU QUẢ khác nhau — create hỏng thì máy KHÔNG
    /// còn được giữ thức, release hỏng thì vẫn đang được giữ đúng như yêu cầu.
    /// Gộp chúng thành một câu "có lỗi xảy ra" là bỏ mất đúng cái người dùng
    /// cần biết để quyết định làm gì tiếp.
    func localizedMessage(in locale: Locale) -> LocalizedStringResource {
        switch self {
        case .couldNotHold(let error):
            "Không giữ được máy thức: hệ thống từ chối \(error.flag.localizedName(in: locale)) (mã \(error.code)). Caffeinate đã tắt."
        case .couldNotRelease(let error):
            "Không gỡ được \(error.flag.localizedName(in: locale)) (mã \(error.code)). Máy vẫn đang được giữ thức đúng như bạn yêu cầu."
        case .unexpected(let debugDescription):
            "Lỗi không xác định: \(debugDescription)"
        }
    }
}

extension CaffeineController {
    /// Câu VoiceOver đọc khi chạm tới icon trên thanh menu. Icon là bề mặt duy
    /// nhất luôn hiện diện, nên nó phải tự nói được trạng thái mà không cần mở
    /// panel ra xem.
    /// Trả về tài nguyên chuỗi chứ không phải `String`: chỉ nơi gọi mới biết
    /// người dùng đang chọn ngôn ngữ nào, và nhãn này phải đổi ngay khi họ đổi.
    func iconAccessibilityDescription(at date: Date) -> LocalizedStringResource {
        if lastFailure != nil {
            return "Caffeinate gặp lỗi"
        }
        guard state.isActive else {
            return "Caffeinate đang tắt"
        }
        guard let endsAt = state.timerEndsAt else {
            return "Caffeinate đang bật, không giới hạn"
        }
        let minutes = Int(max(0, endsAt.timeIntervalSince(date)) / 60)
        return "Caffeinate đang bật, còn \(minutes) phút"
    }
}
