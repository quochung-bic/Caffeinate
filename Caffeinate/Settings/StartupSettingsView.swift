import SwiftUI
import CaffeinateKit

/// "Khởi động" — chạy cùng macOS, và có bật sẵn ngay khi chạy hay không.
struct StartupSettingsView: View {
    @Bindable var controller: CaffeineController
    @State private var launchAtLogin = LaunchAtLogin()
    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                // Xem chú thích trong AutomationSettingsView: trong `Form` trên
                // macOS, nhãn của Toggle không trở thành nhãn trợ năng của công
                // tắc, nên phải gắn tay ở mọi chỗ.
                Toggle("Khởi động cùng macOS", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .accessibilityLabel(Text("Khởi động cùng macOS"))

                Toggle("Bật sẵn ngay khi app khởi chạy",
                       isOn: $controller.settings.activateOnLaunch)
                    .disabled(!launchAtLogin.isEnabled)
                    .accessibilityLabel(Text("Bật sẵn ngay khi app khởi chạy"))
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if !launchAtLogin.isEnabled {
                        // Ràng buộc này phải nói ra: một tuỳ chọn bị mờ đi mà
                        // không giải thích thì trông như lỗi.
                        Text("""
                            Cần bật "Khởi động cùng macOS" trước — nếu app không \
                            tự chạy lúc đăng nhập thì tuỳ chọn kia không có tác dụng.
                            """)
                    }

                    if let error = launchAtLogin.lastError {
                        Label {
                            error.text(in: locale)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
