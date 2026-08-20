import SwiftUI
import AppKit
import CaffeinateKit

/// Panel hiện ra khi bấm icon trên thanh menu — và là giao diện chính của app.
///
/// Chỉ chứa thứ dùng thường xuyên: đang còn bao lâu, chọn thời lượng, tắt.
/// Mọi cấu hình sâu nằm ở cửa sổ Cài đặt. Ranh giới này là có chủ đích: panel
/// phải đọc xong trong một cái liếc, nên mỗi mục thêm vào đây là một mục làm
/// chậm cái liếc đó.
struct ControlPanel: View {
    @Bindable var controller: CaffeineController
    let expiryAlert: TimerExpiryAlert

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            CoffeeGauge(
                endsAt: controller.state.timerEndsAt,
                totalSeconds: controller.timerTotalSeconds,
                isActive: controller.state.isActive,
                size: 104
            )
            .padding(.top, 2)

            DurationBar(
                customMinutes: controller.settings.customDurationMinutes,
                isActive: controller.state.isActive,
                onSelect: { controller.startTimer(minutes: $0) },
                onIndefinite: { controller.startIndefinite() },
                onStop: { controller.stop() }
            )

            StatusCard(
                effectiveFlags: controller.state.effectiveFlags,
                reason: controller.state.activeReason,
                failure: controller.lastFailure
            )

            Divider()

            footer
        }
        .padding(12)
        .frame(width: 288)
        .onAppear {
            // Mở panel nghĩa là người dùng đã thấy rồi; icon không cần nhấp
            // nháy đòi chú ý nữa.
            expiryAlert.cancelFlashing()
        }
    }

    /// Nút thật, không phải chữ xanh: hai hành động này rời khỏi panel (mở cửa
    /// sổ, thoát app) nên phải trông bấm được và có vùng bấm rộng như mọi nút
    /// khác trong panel.
    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                dismiss()
                showSettings()
            } label: {
                Label("Cài đặt…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Thoát", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    /// App chạy ở chế độ phụ trợ (không có icon Dock), nên mở cửa sổ thôi là
    /// chưa đủ — phải tự đưa app lên trước, nếu không cửa sổ Cài đặt sẽ hiện ra
    /// sau lưng ứng dụng đang dùng và người dùng tưởng nút không ăn.
    private func showSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()
    }
}

/// Gom "đang giữ gì" và "vì sao đang bật" vào một khối có nền, thay vì để hai
/// nhóm trôi tự do giữa các khoảng trắng.
private struct StatusCard: View {
    let effectiveFlags: AssertionFlags
    let reason: ActiveReason?
    let failure: AssertionFailure?

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlagGrid(effectiveFlags: effectiveFlags)

            if let reason {
                Divider()
                Label {
                    reason.localizedDescription.text(in: locale)
                } icon: {
                    Image(systemName: reason.symbolName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let failure {
                Divider()
                Label {
                    failure.localizedMessage(in: locale)
                        .text(in: locale)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.red)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.2), value: reason)
    }
}
