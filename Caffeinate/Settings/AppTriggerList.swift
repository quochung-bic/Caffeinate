import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The list of trigger apps.
///
/// An app that has been removed from the Mac stays in the list, just dimmed.
/// Pruning automatically sounds tidy but destroys the user's data: an external
/// drive that is not mounted yet, or an app not reinstalled yet, would be
/// enough to make the configuration vanish without trace.
struct AppTriggerList: View {
    @Binding var bundleIDs: [String]

    @State private var selection: Set<String> = []
    @State private var isPickingFile = false

    private static let listHeight: CGFloat = 116

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if bundleIDs.isEmpty {
                Text("No apps yet. Add one and Caffeinate turns on whenever it’s running.")
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
                Button("Add app…") { isPickingFile = true }
                Button("Remove") {
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
                Text("\(id) — not found")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "questionmark.app.dashed")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text("\(id), not found on this Mac"))
        }
    }
}
