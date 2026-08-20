import SwiftUI
import CaffeinateKit

/// "Tự động" — ba luật bật/tắt độc lập.
struct AutomationSettingsView: View {
    @Bindable var controller: CaffeineController

    var body: some View {
        Form {
            Section {
                // `.accessibilityLabel` trên MỌI Toggle trong cửa sổ này là
                // bắt buộc, kể cả khi nhãn đã khai báo bằng chuỗi thuần: trong
                // `Form` trên macOS, nhãn được vẽ thành một dòng chữ riêng cạnh
                // công tắc chứ không gắn vào công tắc, nên VoiceOver đọc ra
                // toàn "switch, off" không phân biệt được cái nào với cái nào.
                Toggle("Một app trong danh sách đang chạy",
                       isOn: $controller.settings.appTriggerEnabled)
                    .accessibilityLabel(Text("Một app trong danh sách đang chạy"))

                AppTriggerList(bundleIDs: $controller.settings.triggerAppBundleIDs)
                    .disabled(!controller.settings.appTriggerEnabled)
            } header: {
                Text("Tự bật khi")
            }

            Section {
                Toggle("Đang cắm sạc",
                       isOn: $controller.settings.chargingTriggerEnabled)
                    .accessibilityLabel(Text("Đang cắm sạc"))
                Toggle("Có màn hình ngoài",
                       isOn: $controller.settings.externalDisplayTriggerEnabled)
                    .accessibilityLabel(Text("Có màn hình ngoài"))
            } footer: {
                Text("""
                    Nút Tắt luôn thắng: nó gỡ cả những luật đang đúng. Một luật \
                    chỉ bật lại khi điều kiện của nó thật sự tái diễn — rút sạc \
                    rồi cắm lại, chứ không phải vài giây sau đó.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}
