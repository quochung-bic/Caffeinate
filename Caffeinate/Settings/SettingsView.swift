import SwiftUI
import CaffeinateKit

/// Cửa sổ Cài đặt — khung nhìn phụ, mở hay đóng không ảnh hưởng gì tới việc app
/// có đang giữ máy thức hay không.
///
/// Chia bốn tab thay vì một biểu mẫu dài: mỗi tab trả lời đúng một câu hỏi
/// ("giữ cái gì", "khi nào tự bật", "chạy lúc nào", "app này là gì"), nên tìm
/// một mục không cần cuộn qua những mục không liên quan.
struct SettingsView: View {
    @Bindable var controller: CaffeineController
    @Bindable var language: LanguagePreference

    /// Chiều rộng đủ để thanh tab luôn hiện thẳng ra. Hẹp hơn thì macOS 26 gộp
    /// hết tab vào nút tràn "»", biến bốn tab thành một menu hai cấp.
    private static let width: CGFloat = 500

    var body: some View {
        TabView {
            GeneralSettingsView(controller: controller, language: language)
                .tabItem { Label("Chung", systemImage: "gearshape") }

            AutomationSettingsView(controller: controller)
                .tabItem { Label("Tự động", systemImage: "bolt") }

            StartupSettingsView(controller: controller)
                .tabItem { Label("Khởi động", systemImage: "power") }

            AboutSettingsView()
                .tabItem { Label("Giới thiệu", systemImage: "info.circle") }
        }
        .frame(width: Self.width)
        .background(CloseWindowShortcut())
    }
}

/// App chạy ở chế độ phụ trợ nên không sở hữu thanh menu, và không có thanh
/// menu thì cũng không có mục File > Close — tức ⌘W chết. Nút ẩn này gắn lại
/// đúng phím tắt đó, vì một cửa sổ macOS đóng được bằng ⌘W là kỳ vọng cơ bản.
private struct CloseWindowShortcut: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Đóng cửa sổ") { dismiss() }
            .keyboardShortcut("w", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}
