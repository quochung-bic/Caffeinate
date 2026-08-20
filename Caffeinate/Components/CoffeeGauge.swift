import SwiftUI

/// Ly cà phê + thời gian còn lại. Không có vòng tiến trình: mực cà phê ĐÃ LÀ
/// thanh tiến trình rồi, thêm một cái vòng nữa là nói cùng một điều hai lần.
///
/// Thời gian luôn tính lại từ `endsAt` chứ không đếm lùi bằng biến riêng, nên
/// máy ngủ rồi thức dậy vẫn không lệch số.
///
/// # Ba nhịp, không phải một
///
/// Trước đây cả khối nằm trong MỘT `TimelineView` chạy 24 fps, nên mỗi khung
/// hình dựng lại luôn cả phần tử trợ năng bọc ngoài. Hậu quả không chỉ là tốn
/// CPU: cây accessibility không bao giờ đứng yên, VoiceOver mất chỗ bám và một
/// truy vấn UI test lên nó chạy tới lúc hết giờ mà không xong.
///
/// Giờ mỗi thứ chạy đúng nhịp nó cần:
/// - ly (khói + mực cà phê): 20 fps, và dừng hẳn khi không hoạt động;
/// - số đếm ngược: 1 Hz, và chỉ tồn tại khi thật sự có hẹn giờ;
/// - nhãn trợ năng: KHÔNG có nhịp nào — nó nói "hẹn giờ tới 15:47" thay vì
///   "còn 14 phút", nên đứng yên suốt lần hẹn giờ. Một nhãn đổi mỗi giây là
///   nhãn mà VoiceOver đọc lại không ngừng, tức là tệ hơn không có.
struct CoffeeGauge: View {
    let endsAt: Date?
    let totalSeconds: TimeInterval
    let isActive: Bool
    var size: CGFloat = 150

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Hợp đồng với `SmokeTests`.
    static let accessibilityIdentifier = "caffeine-gauge"

    /// 20 fps, không phải 24 hay 60.
    ///
    /// Khói là chuyển động hữu cơ, chậm; ở 20 fps mắt không phân biệt được với
    /// 60, còn máy thì vẽ ít hơn ba lần. Với một ứng dụng mà lý do tồn tại là
    /// quản lý năng lượng, đốt GPU để làm mượt một sợi khói là tự mâu thuẫn.
    private static let animatedInterval = 1.0 / 20.0

    var body: some View {
        VStack(spacing: size * 0.04) {
            cup
            readout
        }
        .animation(.easeOut(duration: 0.45), value: mode)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        // Định danh cố định để bộ UI test tìm thẳng tới phần tử này thay vì
        // quét toàn cây theo nhãn: cây đang có hoạt ảnh nên một truy vấn diện
        // rộng phải chờ nó đứng yên, mà nó thì không bao giờ đứng yên.
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    // MARK: - Ly

    private var cup: some View {
        // Giảm chuyển động thì khói tắt, nên chỉ còn mực cà phê cần cập nhật —
        // 1 Hz là đủ. Không hoạt động thì dừng hẳn timeline thay vì vẽ lại liên
        // tục một cái ly đứng yên.
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 1 : Self.animatedInterval,
                paused: !isActive
            )
        ) { context in
            CoffeeCup(
                fill: fill(at: context.date),
                isActive: isActive,
                steamPhase: context.date.timeIntervalSinceReferenceDate * 0.3,
                showSteam: isActive && !reduceMotion,
                size: size
            )
        }
        .accessibilityHidden(true)
    }

    // MARK: - Số

    @ViewBuilder
    private var readout: some View {
        if let endsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                readout(remaining: max(0, endsAt.timeIntervalSince(context.date)))
            }
        } else {
            // Không có hẹn giờ thì không có gì đếm: "∞" hay "—" đứng yên, nên
            // không dựng timeline nào cả.
            readout(remaining: nil)
        }
    }

    private func readout(remaining: TimeInterval?) -> some View {
        VStack(spacing: 2) {
            Text(numberLabel(remaining: remaining))
                .font(.system(size: size * 0.2, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(caption)
                .font(.system(size: max(9, size * 0.062), weight: .semibold))
                .tracking(1.3)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Dẫn xuất

    private enum Mode: Int { case off, indefinite, countdown }

    private var mode: Mode {
        guard isActive else { return .off }
        return endsAt == nil ? .indefinite : .countdown
    }

    private func fill(at now: Date) -> Double {
        guard isActive else { return 0 }
        guard let endsAt, totalSeconds > 0 else { return 1 }
        let remaining = max(0, endsAt.timeIntervalSince(now))
        return min(max(remaining / totalSeconds, 0), 1)
    }

    private func numberLabel(remaining: TimeInterval?) -> String {
        guard let remaining else { return isActive ? "∞" : "—" }
        let total = Int(remaining)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private var caption: LocalizedStringKey {
        switch mode {
        case .countdown:    "còn lại"
        case .indefinite:   "không giới hạn"
        case .off:          "đang tắt"
        }
    }

    /// Nhãn này là hợp đồng với bộ UI test — nó là cách đáng tin nhất để đọc ra
    /// trạng thái active từ ngoài tiến trình. Đổi câu chữ ở đây thì phải đổi cả
    /// `SmokeTests`.
    private var accessibilityLabel: Text {
        switch mode {
        case .off:
            Text("Đang tắt")
        case .indefinite:
            Text("Đang bật, không giới hạn")
        case .countdown:
            // Mốc kết thúc thay vì thời gian còn lại: chính xác hơn khi đọc
            // thành lời, và đứng yên suốt lần hẹn giờ.
            Text("Đang bật, hẹn giờ tới \(endsAtLabel)")
        }
    }

    private var endsAtLabel: String {
        endsAt?.formatted(date: .omitted, time: .shortened) ?? ""
    }
}
