import SwiftUI
import CaffeinateKit

/// "Chung" — ngôn ngữ giao diện, bốn cờ giữ thức, và mốc thời lượng tuỳ chỉnh.
struct GeneralSettingsView: View {
    @Bindable var controller: CaffeineController
    @Bindable var language: LanguagePreference

    @Environment(\.locale) private var locale

    var body: some View {
        Form {
            Section {
                Picker(selection: $language.selection) {
                    Text("Theo hệ thống").tag(AppLanguage.system)
                    // Tên ngôn ngữ luôn viết bằng chính ngôn ngữ đó, không dịch.
                    // Người đang lạc trong một giao diện họ không đọc được vẫn
                    // phải nhận ra dòng dẫn họ về nhà.
                    Text(verbatim: "Tiếng Việt").tag(AppLanguage.vietnamese)
                    Text(verbatim: "English").tag(AppLanguage.english)
                } label: {
                    Text("Ngôn ngữ")
                }
                // Nhãn của `Picker`/`Toggle`/`Stepper` trong Form trên macOS
                // được vẽ như một dòng chữ RIÊNG cạnh control, chứ không gắn
                // vào chính control. Hệ quả: VoiceOver đọc "pop up button,
                // Theo hệ thống" mà không nói được đó là cái gì. Phải gắn tay.
                .accessibilityLabel(Text("Ngôn ngữ"))
            } header: {
                Text("Giao diện")
            } footer: {
                Text("""
                    Giao diện đổi ngay. Các hộp thoại do macOS vẽ hộ — chọn app, \
                    xin quyền thông báo — sẽ đổi từ lần mở app sau.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(AssertionFlags.all, id: \.rawValue) { flag in
                    Toggle(isOn: binding(for: flag)) {
                        VStack(alignment: .leading, spacing: 2) {
                            flag.localizedName.text(in: locale)
                            flag.localizedExplanation.text(in: locale)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // Nhãn dựng bằng `VStack` không trở thành nhãn trợ năng của
                    // công tắc — nó chỉ là hình vẽ. Không gắn tay thì VoiceOver
                    // đọc bốn công tắc giống hệt nhau: "switch, on".
                    .accessibilityLabel(flag.localizedName.text(in: locale))
                    .accessibilityHint(flag.localizedExplanation.text(in: locale))
                }
            } header: {
                Text("Khi Caffeinate bật, giữ những gì")
            } footer: {
                Text("Mặc định chỉ giữ hệ thống. Đó thường là thứ duy nhất bạn cần.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $controller.settings.customDurationMinutes,
                        in: Settings.durationRange,
                        step: 5) {
                    LabeledContent {
                        Text("\(controller.settings.customDurationMinutes) phút")
                            .monospacedDigit()
                    } label: {
                        Text("Thời lượng tuỳ chỉnh")
                    }
                }
                .accessibilityLabel(Text("Thời lượng tuỳ chỉnh"))
            } header: {
                Text("Hẹn giờ")
            } footer: {
                Text("Mốc này xuất hiện thành nút thứ tư trên panel, cạnh 15p / 30p / 1h.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for flag: AssertionFlags) -> Binding<Bool> {
        Binding(
            get: { controller.settings.flags.contains(flag) },
            set: { isOn in
                if isOn {
                    controller.settings.flags.insert(flag)
                } else {
                    controller.settings.flags.remove(flag)
                }
            }
        )
    }
}
