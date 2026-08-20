import SwiftUI
import CaffeinateKit

/// Bốn chấm trạng thái. Đặc = đang thực sự giữ assertion đó.
///
/// Hiển thị cả cờ đang tắt chứ không chỉ cờ đang bật: người dùng cần thấy toàn
/// cảnh để biết mình đang KHÔNG giữ gì, chứ không phải đoán từ một danh sách
/// rút gọn.
struct FlagGrid: View {
    let effectiveFlags: AssertionFlags

    @Environment(\.locale) private var locale

    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(AssertionFlags.all, id: \.rawValue) { flag in
                indicator(for: flag)
            }
        }
    }

    private func indicator(for flag: AssertionFlags) -> some View {
        let isOn = effectiveFlags.contains(flag)
        return Label {
            flag.localizedName.text(in: locale)
                .foregroundStyle(isOn ? .primary : .secondary)
        } icon: {
            Image(systemName: isOn ? "circle.fill" : "circle")
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .imageScale(.small)
        }
        .font(.callout)
        .animation(.easeInOut(duration: 0.15), value: isOn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flag.localizedName.text(in: locale))
        .accessibilityValue(isOn ? Text("đang giữ") : Text("không giữ"))
    }
}
