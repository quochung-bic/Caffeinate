import SwiftUI

/// Hàng nút chọn thời lượng. Không giữ trạng thái — mọi hành động bắn ra ngoài.
struct DurationBar: View {
    let customMinutes: Int
    let isActive: Bool
    var onSelect: (Int) -> Void
    var onIndefinite: () -> Void
    var onStop: () -> Void

    private static let quickDurations = [15, 30, 60]

    /// Hai hàng thay vì một: nhồi năm nút vào một hàng làm nhãn thời lượng bị
    /// cắt cụt trong panel hẹp, mà nhãn chính là thông tin duy nhất của nút.
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Self.quickDurations, id: \.self) { minutes in
                    durationButton(minutes)
                }
                durationButton(customMinutes)
            }

            HStack(spacing: 6) {
                Button {
                    onIndefinite()
                } label: {
                    Label("Không giới hạn", systemImage: "infinity")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(Text("Bật không giới hạn"))

                Button {
                    onStop()
                } label: {
                    // "Tắt" chỉ cần đủ chỗ cho chính nó; phần dư nhường hết cho
                    // nhãn dài bên trái, nếu chia đôi thì nó bị cắt thành
                    // "Không giới h…".
                    Label("Tắt", systemImage: "stop.fill")
                        .frame(minWidth: 56)
                }
                .disabled(!isActive)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .lineLimit(1)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func durationButton(_ minutes: Int) -> some View {
        Button { onSelect(minutes) } label: {
            label(for: minutes)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text("Bật trong \(minutes) phút"))
    }

    /// Trả `Text` chứ không phải `String`: `Text` tra chuỗi theo `\.locale` của
    /// environment, nên nút đổi ngôn ngữ ngay khi người dùng đổi lựa chọn.
    /// `String(localized:)` thì bám theo ngôn ngữ của tiến trình và sẽ đứng im.
    ///
    /// Bội số của 60 hiển thị theo giờ cho gọn; còn lại dùng phút. Nhãn phải vừa
    /// một dòng trong panel 288pt nên không có chỗ cho "60 phút".
    private func label(for minutes: Int) -> Text {
        minutes % 60 == 0 ? Text("\(minutes / 60)h") : Text("\(minutes)p")
    }
}
