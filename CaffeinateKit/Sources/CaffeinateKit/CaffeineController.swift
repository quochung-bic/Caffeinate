import Foundation
import Observation

/// Nguồn sự thật cho UI và là chỗ DUY NHẤT gọi `AssertionManager.set(flags:)`.
/// Mọi thay đổi đi qua `send(_:) → reduce → apply()`. Không có đường tắt nào khác.
///
/// Sống trong package (không phải app target) vì nó không phụ thuộc SwiftUI/AppKit
/// — chỉ Foundation, Observation và phần còn lại của CaffeinateKit — nên có thể
/// kiểm thử bằng `swift test` với backing/trigger giả, không cần dựng cả app.
@MainActor
@Observable
public final class CaffeineController {
    public private(set) var state = CaffeineState()

    /// Sự cố gần nhất, ở dạng dữ liệu. Tầng app dịch nó thành câu chữ.
    public private(set) var lastFailure: AssertionFailure?

    /// Tổng thời lượng của lần hẹn giờ hiện tại — cần để tính tỉ lệ mực cà phê.
    public private(set) var timerTotalSeconds: TimeInterval = 0

    /// Nhịp một giây, CHỈ chạy trong lúc đếm ngược.
    ///
    /// Vì sao nhịp này sống ở đây chứ không ở tầng giao diện: nhãn của
    /// `MenuBarExtra` KHÔNG chạy `TimelineView`. Đã đo — trong 8 giây có hẹn
    /// giờ, một nhãn dựng bằng `TimelineView(.periodic(by: 1))` chỉ được vẽ lại
    /// 2 lần, cả hai đều do trạng thái đổi. Icon sẽ đứng im ở mức đầy suốt lần
    /// hẹn giờ, tức là mất hẳn tính năng chính của nó.
    ///
    /// Cách duy nhất đáng tin để buộc nhãn vẽ lại là cho nó đọc một thuộc tính
    /// `@Observable` thật sự thay đổi. Đó là `now`.
    ///
    /// `iconState(at:)` vẫn nhận thời điểm từ ngoài chứ không tự đọc `Date()`,
    /// nên phần tính toán vẫn thuần tuý và test được mà không cần chờ đồng hồ.
    public private(set) var now: Date = .now

    /// Gọi khi hẹn giờ chạy hết giờ (không phải khi người dùng tự dừng).
    /// Tầng app dùng nó để báo cho người dùng biết; package không tự làm việc
    /// đó vì thông báo/âm thanh là chuyện của AppKit, không phải của lõi.
    @ObservationIgnored public var onTimerExpired: (@MainActor () -> Void)?

    /// Gọi mỗi khi một lần hẹn giờ bắt đầu. Tầng app dùng để xin quyền thông
    /// báo đúng lúc người dùng vừa làm việc sẽ dẫn tới thông báo.
    @ObservationIgnored public var onTimerStarted: (@MainActor () -> Void)?

    @ObservationIgnored private let assertions: AssertionManager
    @ObservationIgnored private let store: any SettingsStoring
    @ObservationIgnored private let triggerFactory: TriggerFactory
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private var tickerTask: Task<Void, Never>?
    @ObservationIgnored private var engine: TriggerEngine?

    public var settings: Settings {
        didSet {
            store.settings = settings
            send(.flagsChanged(settings.flags))
            if settings.appTriggerEnabled != oldValue.appTriggerEnabled
                || settings.chargingTriggerEnabled != oldValue.chargingTriggerEnabled
                || settings.externalDisplayTriggerEnabled != oldValue.externalDisplayTriggerEnabled
                || settings.triggerAppBundleIDs != oldValue.triggerAppBundleIDs {
                rebuildTriggers()
            }
        }
    }

    /// Cách dựng bộ trigger từ settings hiện hành. Tách thành seam để test
    /// tiêm được `FakeTrigger` mà không cần chạm IOKit/NSWorkspace/NSScreen
    /// thật — production dùng `defaultTriggerFactory`, test tự truyền factory
    /// của mình qua init chỉ định bên dưới.
    typealias TriggerFactory = @MainActor (Settings) -> [any Trigger]

    public convenience init(
        assertions: AssertionManager = AssertionManager(
            backing: IOKitBacking(),
            reason: AssertionManager.defaultReason
        ),
        store: any SettingsStoring = UserDefaultsSettingsStore()
    ) {
        self.init(assertions: assertions, store: store, triggerFactory: Self.defaultTriggerFactory)
    }

    /// Init chỉ định — nhận thêm `triggerFactory` để test tiêm trigger giả.
    /// Không public: chỉ dùng nội bộ module (production đi qua init tiện lợi
    /// ở trên; test dùng `@testable import` để chạm tới init này).
    init(
        assertions: AssertionManager,
        store: any SettingsStoring,
        triggerFactory: @escaping TriggerFactory
    ) {
        self.assertions = assertions
        self.store = store
        self.triggerFactory = triggerFactory
        self.settings = store.settings
        self.state.flags = store.settings.flags

        if store.settings.activateOnLaunch {
            send(.toggledManually(true))
        }

        rebuildTriggers()
    }

    private static let defaultTriggerFactory: TriggerFactory = { settings in
        var triggers: [any Trigger] = []
        if settings.appTriggerEnabled, !settings.triggerAppBundleIDs.isEmpty {
            triggers.append(AppRunningTrigger(bundleIDs: settings.triggerAppBundleIDs))
        }
        if settings.chargingTriggerEnabled {
            triggers.append(PowerSourceTrigger())
        }
        if settings.externalDisplayTriggerEnabled {
            triggers.append(ExternalDisplayTrigger())
        }
        return triggers
    }

    public func send(_ event: CaffeineEvent) {
        state = reduce(state, event)
        apply()
        syncTicker()
    }

    // MARK: - Hành động của người dùng

    /// Bật/tắt thủ công.
    ///
    /// Ngữ nghĩa "Tắt" (nhánh `state.isActive`, gửi `.stopAll`) là DỨT KHOÁT:
    /// nó xoá manual + timer + MỌI lý do trigger đang có trong `state`, nhưng
    /// KHÔNG đụng tới trạng thái nội bộ (baseline) của từng trigger — ví dụ
    /// `PowerSourceTrigger.isCharging` vẫn giữ nguyên `true` nếu máy vẫn đang
    /// cắm sạc. Trigger chỉ phát `.triggerFired` lại trên một chuyển tiếp
    /// false→true THẬT SỰ (rút sạc rồi cắm lại), không phải mỗi lần có sự
    /// kiện trạng thái mới mà điều kiện không đổi. Vì vậy bấm Tắt trong khi
    /// đang sạc sẽ tắt hẳn, và KHÔNG tự bật lại vài giây sau chỉ vì hệ thống
    /// gửi thêm một thông báo "vẫn đang sạc". Đây là hành vi có chủ đích —
    /// không được "sửa" thành reset baseline trigger lúc stopAll, vì làm vậy
    /// sẽ khiến rule tự động bật lại ngay ở lần cập nhật trạng thái kế tiếp
    /// trong khi điều kiện chưa hề đổi, phá vỡ tính dứt khoát của nút Tắt.
    ///
    /// Trường hợp biên đã được chấp nhận (không cố sửa): nếu sau đó người
    /// dùng đổi một setting bất kỳ khiến `rebuildTriggers()` chạy lại, bộ
    /// trigger mới sẽ tự `refresh()` và có thể phát hiện điều kiện vẫn đúng
    /// (ví dụ vẫn đang sạc) rồi bật lại rule đó ngay. Đó là hệ quả hợp lý của
    /// "rule đang bật + điều kiện đúng → active khi đánh giá lại từ đầu", nên
    /// không thêm state để chặn.
    public func toggle() {
        if state.isActive {
            stop()
        } else {
            startIndefinite()
        }
    }

    /// Tắt dứt khoát.
    public func stop() {
        cancelTimerTask()
        send(.stopAll)
    }

    /// Bật không giới hạn. Huỷ luôn hẹn giờ đang chạy — reduce đã xoá
    /// `timerEndsAt`, nhưng Task hẹn giờ vẫn sống nếu không huỷ ở đây và sẽ
    /// bắn `.timerExpired` muộn.
    public func startIndefinite() {
        cancelTimerTask()
        send(.toggledManually(true))
    }

    /// Bật trong `minutes` phút rồi tự tắt phần hẹn giờ.
    /// `minutes` bị kẹp về khoảng hợp lệ — đây là API public, không thể giả
    /// định người gọi đã kiểm tra hộ.
    public func startTimer(minutes: Int) {
        let minutes = min(
            max(minutes, Settings.durationRange.lowerBound),
            Settings.durationRange.upperBound
        )
        timerTask?.cancel()

        let seconds = TimeInterval(minutes * 60)
        let endsAt = Date().addingTimeInterval(seconds)
        timerTotalSeconds = seconds
        send(.startedTimer(until: endsAt))
        onTimerStarted?()

        timerTask = Task { [weak self] in
            // Ngủ theo từng chặng ngắn rồi ĐỌC LẠI ĐỒNG HỒ, thay vì ngủ một
            // phát đúng bằng thời lượng. `Task.sleep` chỉ hứa "ít nhất chừng
            // này", và giữa chừng máy có thể ngủ/thức hoặc người dùng chỉnh
            // giờ hệ thống — ngủ một phát thì sai số đó không bao giờ được
            // phát hiện, còn ở đây nó tự chỉnh lại sau tối đa một chặng.
            while !Task.isCancelled {
                let remaining = endsAt.timeIntervalSinceNow
                guard remaining > 0 else { break }
                try? await Task.sleep(for: .seconds(min(remaining, 60)))
            }
            guard !Task.isCancelled, let self else { return }
            self.send(.timerExpired)
            // Chỉ chạy khi hẹn giờ đi hết quãng đường của nó. Bấm Tắt hay
            // chuyển sang "không giới hạn" đều huỷ Task này, nên không có
            // chuyện báo "hết giờ" cho một lần hẹn giờ mà người dùng tự dừng.
            self.onTimerExpired?()
        }
    }

    /// Giải phóng tường minh khi app thoát. An toàn để gọi nhiều lần.
    public func shutdown() {
        cancelTimerTask()
        tickerTask?.cancel()
        tickerTask = nil
        engine?.stop()
        engine = nil
        assertions.releaseAll()
    }

    // MARK: - Dẫn xuất cho giao diện

    /// Còn đang đếm ngược hay không. UI dùng để biết có cần nhịp đồng hồ không
    /// — không có hẹn giờ thì không có gì thay đổi theo thời gian để mà vẽ lại.
    public var isCountingDown: Bool {
        state.timerEndsAt != nil
    }

    /// Trạng thái icon menu bar TẠI một thời điểm cho trước.
    ///
    /// Nhận `date` từ ngoài thay vì tự đọc `Date()`: trước đây controller nuôi
    /// một `Task` đánh nhịp mỗi giây chỉ để cập nhật một biến `now`, chạy song
    /// song với `TimelineView` của giao diện — hai đồng hồ cho cùng một việc.
    /// Giờ giao diện là chỗ duy nhất giữ nhịp, còn hàm này thuần tuý theo thời
    /// gian nên cũng test được mà không cần chờ đồng hồ thật chạy.
    public func iconState(at date: Date) -> MenuBarIconState {
        MenuBarIconState(
            isActive: state.isActive,
            progress: timerProgress(at: date),
            hasError: lastFailure != nil
        )
    }

    /// nil khi đang bật không giới hạn — icon sẽ vẽ ly đầy thay vì vơi dần.
    private func timerProgress(at date: Date) -> Double? {
        guard let endsAt = state.timerEndsAt, timerTotalSeconds > 0 else { return nil }
        return max(0, endsAt.timeIntervalSince(date)) / timerTotalSeconds
    }

    // MARK: - Nội bộ

    /// Bật nhịp khi có hẹn giờ, tắt khi không. Không để đồng hồ quay không tải:
    /// ngoài lúc đếm ngược thì chẳng có gì thay đổi theo thời gian để mà vẽ.
    private func syncTicker() {
        guard state.timerEndsAt != nil else {
            tickerTask?.cancel()
            tickerTask = nil
            return
        }
        guard tickerTask == nil else { return }

        now = .now
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.now = .now
            }
        }
    }

    private func cancelTimerTask() {
        timerTask?.cancel()
        timerTask = nil
        // Về 0 để vòng tính tỉ lệ không còn mốc cũ để chia.
        timerTotalSeconds = 0
    }

    /// Dựng lại bộ trigger theo cài đặt hiện tại. Gọi lại mỗi khi settings đổi.
    /// Không public: chỉ `settings` didSet và init trong module này gọi tới —
    /// app target không cần và không nên gọi thẳng, để tránh bỏ qua luồng
    /// "settings đổi → rebuild" có chủ đích.
    func rebuildTriggers() {
        engine?.stop()

        // TriggerEngine.stop() đặt isRunning = false trước khi gọi stop() của
        // từng trigger, và onChange bị chặn theo isRunning — nên sự kiện "tắt"
        // mà trigger cũ cố phát ra lúc dừng sẽ bị nuốt (đây là thiết kế có chủ
        // đích, xem test silentAfterStop). Vì vậy phải tự tay xoá hết các lý
        // do trigger còn sót lại từ cấu hình cũ, KHÔNG phân biệt bộ trigger
        // mới rỗng hay không — nếu chỉ xoá khi rỗng thì lý do nào bị bộ
        // trigger mới bỏ sót (ví dụ tắt App-trigger nhưng vẫn còn
        // Charging-trigger) sẽ kẹt lại vĩnh viễn. Không dùng .stopAll: nó
        // cũng xoá cả manual/timer, không phải điều ta muốn ở đây.
        // Chụp lại tập hợp trước vì send() làm thay đổi state khi đang lặp.
        for reason in state.triggerReasons {
            send(.triggerCleared(reason))
        }

        let triggers = triggerFactory(settings)

        guard !triggers.isEmpty else {
            engine = nil
            return
        }

        // start() gọi refresh() ngay cho mỗi trigger, nên lý do nào vẫn còn
        // đúng dưới cấu hình mới (ví dụ vẫn đang cắm sạc) sẽ được phát lại
        // .triggerFired ngay lập tức — không mất trạng thái thật.
        let engine = TriggerEngine(triggers: triggers)
        engine.onEvent = { [weak self] event in
            self?.send(event)
        }
        engine.start()
        self.engine = engine
    }

    /// Chỗ duy nhất chạm tới `AssertionManager`. Lỗi tạo thì tắt hẳn và báo,
    /// không giả vờ đang bật. Lỗi release không làm mất hiệu lực các cờ vừa tạo
    /// thành công nên chỉ báo cho người dùng biết, không ép trạng thái về tắt.
    private func apply() {
        do {
            try assertions.set(flags: state.effectiveFlags)
            if let releaseError = assertions.lastReleaseError {
                lastFailure = .couldNotRelease(releaseError)
            } else {
                lastFailure = nil
            }
        } catch let error as AssertionError {
            lastFailure = .couldNotHold(error)
            state = reduce(state, .stopAll)
            assertions.releaseAll()
        } catch {
            lastFailure = .unexpected(debugDescription: String(describing: error))
            state = reduce(state, .stopAll)
            assertions.releaseAll()
        }
    }
}
