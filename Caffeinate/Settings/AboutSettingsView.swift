import SwiftUI
import AppKit

/// Tab tĩnh: không đọc, không sửa state. Giải thích app làm gì và những chỗ dễ
/// hiểu nhầm.
struct AboutSettingsView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                section("Dùng thế nào") {
                    bullet("Bấm icon ly cà phê trên thanh menu để mở bảng điều khiển.")
                    bullet("Chọn một mốc thời gian — hết giờ là máy tự trở về bình thường.")
                    bullet("Chọn \"Không giới hạn\" nếu chưa biết cần bao lâu.")
                    bullet("Bấm \"Tắt\" để dừng ngay, kể cả khi đang có luật tự động chạy.")
                }

                section("Mực cà phê là thanh tiến trình") {
                    paragraph("""
                        Ly đầy khi vừa bật và vơi dần theo đồng hồ đếm ngược. Cùng \
                        một hình đó thu nhỏ thành icon trên thanh menu, nên liếc \
                        một cái là biết còn bao lâu mà không cần mở gì.
                        """)
                }

                section("Khi hết giờ") {
                    paragraph("""
                        Caffeinate báo bằng ba đường độc lập — banner thông báo, \
                        một tiếng chuông, và icon nhấp nháy — vì đường nào cũng có \
                        lúc câm: banner bị Do Not Disturb chặn, âm thanh vô nghĩa \
                        khi tai nghe ở phòng khác, còn icon thì chỉ thấy nếu đang \
                        nhìn lên thanh menu.
                        """)
                }

                footer
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Caffeinate")
                    .font(.title2.bold())
                Text("Giữ cho máy khỏi ngủ, khi nào bạn muốn.")
                    .foregroundStyle(.secondary)
                Self.versionResource.text(in: locale)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }

    private var footer: some View {
        Text(Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "")
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    /// Đọc từ bundle chứ không viết cứng: một số phiên bản chép tay trong mã là
    /// một số phiên bản sớm muộn cũng sai.
    private static var versionResource: LocalizedStringResource {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Phiên bản \(short) (\(build))"
    }

    private func section(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
    }
}
