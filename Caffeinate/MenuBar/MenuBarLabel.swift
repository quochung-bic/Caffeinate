import SwiftUI
import CaffeinateKit

/// Icon trên thanh menu.
///
/// # Vì sao ở đây không có `TimelineView`
///
/// Nhãn của `MenuBarExtra` không phải một view bình thường: SwiftUI kết xuất nó
/// vào một `NSStatusItem`, và trong khung đó `TimelineView` KHÔNG chạy nhịp.
/// Đã đo, không phải suy đoán: trong 8 giây đang đếm ngược, một nhãn dựng bằng
/// `TimelineView(.periodic(by: 1))` chỉ được vẽ lại 2 lần, cả hai đều do trạng
/// thái đổi. Icon đứng im ở mức đầy suốt lần hẹn giờ — mất hẳn thứ khiến nó
/// đáng có mặt trên thanh menu.
///
/// Cách đáng tin duy nhất để nhãn vẽ lại là đọc một thuộc tính `@Observable`
/// thật sự thay đổi: `controller.now`, do controller đánh nhịp và chỉ chạy khi
/// có hẹn giờ. Ngoài lúc đếm ngược, view này không đọc `now` nên không có phụ
/// thuộc nào theo thời gian — nó chỉ vẽ lại khi trạng thái đổi.
struct MenuBarLabel: View {
    let controller: CaffeineController
    let expiryAlert: TimerExpiryAlert
    /// Nhãn này nằm ngoài mọi scene nên không có `\.locale` để dựa vào; nó đọc
    /// thẳng lựa chọn ngôn ngữ, và vì đó là `@Observable` nên đổi ngôn ngữ là
    /// nhãn VoiceOver đổi theo ngay.
    let language: LanguagePreference

    var body: some View {
        Image(nsImage: nsImage(at: controller.isCountingDown ? controller.now : .now))
    }

    private func nsImage(at date: Date) -> NSImage {
        let description = language.resolve(controller.iconAccessibilityDescription(at: date))
        // Nhịp "tắt" của hiệu ứng nhấp nháy báo hết giờ.
        if expiryAlert.isFlashing {
            return MenuBarIcon.blankImage(accessibilityDescription: description)
        }
        return MenuBarIcon.cachedImage(
            for: controller.iconState(at: date),
            accessibilityDescription: description
        )
    }
}
