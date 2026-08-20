import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Danh sách app kích hoạt.
///
/// App đã bị gỡ khỏi máy vẫn nằm lại trong danh sách, chỉ hiện mờ. Tự động xoá
/// nghe có vẻ gọn nhưng nó phá dữ liệu của người dùng: một ổ đĩa ngoài chưa gắn
/// hay một app tạm thời chưa cài lại cũng đủ để cấu hình biến mất không dấu vết.
struct AppTriggerList: View {
    @Binding var bundleIDs: [String]

    @State private var selection: Set<String> = []
    @State private var isPickingFile = false

    private static let listHeight: CGFloat = 116

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if bundleIDs.isEmpty {
                Text("Chưa có app nào. Thêm app để Caffeinate tự bật khi app đó chạy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.listHeight)
            } else {
                List(bundleIDs, id: \.self, selection: $selection) { id in
                    row(for: id)
                }
                .frame(height: Self.listHeight)
                .border(.quaternary)
            }

            HStack {
                Button("Thêm app…") { isPickingFile = true }
                Button("Xoá") {
                    bundleIDs.removeAll { selection.contains($0) }
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)
            }
            .controlSize(.small)
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.application]
        ) { result in
            guard case .success(let url) = result,
                  let bundle = Bundle(url: url),
                  let id = bundle.bundleIdentifier,
                  !bundleIDs.contains(id)
            else { return }
            bundleIDs.append(id)
        }
    }

    @ViewBuilder
    private func row(for id: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Label {
                Text(url.deletingPathExtension().lastPathComponent)
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        } else {
            Label {
                Text("\(id) — không tìm thấy")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "questionmark.app.dashed")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text("\(id), không tìm thấy trên máy"))
        }
    }
}
