import Foundation
import Testing
@testable import CaffeinateKit

/// Dựng bộ trigger giả theo đúng luật production (app/charging/external theo
/// settings) nhưng bằng `FakeTrigger`, và giữ tham chiếu tới trigger MỚI NHẤT
/// của mỗi loại — vì `rebuildTriggers()` tạo trigger mới mỗi lần settings đổi,
/// giống hệt cách production luôn tạo `AppRunningTrigger`/`PowerSourceTrigger`/
/// `ExternalDisplayTrigger` mới. Đây là seam duy nhất cần thêm để
/// `CaffeineController` kiểm thử được mà không chạm IOKit/NSWorkspace/NSScreen.
@MainActor
private final class TriggerSpy {
    private(set) var appTrigger: FakeTrigger?
    private(set) var chargingTrigger: FakeTrigger?
    private(set) var externalDisplayTrigger: FakeTrigger?

    func makeTriggers(for settings: Settings) -> [any Trigger] {
        var triggers: [any Trigger] = []

        if settings.appTriggerEnabled, !settings.triggerAppBundleIDs.isEmpty {
            let t = FakeTrigger()
            appTrigger = t
            triggers.append(t)
        } else {
            appTrigger = nil
        }

        if settings.chargingTriggerEnabled {
            let t = FakeTrigger()
            chargingTrigger = t
            triggers.append(t)
        } else {
            chargingTrigger = nil
        }

        if settings.externalDisplayTriggerEnabled {
            let t = FakeTrigger()
            externalDisplayTrigger = t
            triggers.append(t)
        } else {
            externalDisplayTrigger = nil
        }

        return triggers
    }
}

@Suite("CaffeineController")
@MainActor
struct CaffeineControllerTests {

    private func makeController(
        settings: Settings = Settings(),
        backing: FakeBacking = FakeBacking(),
        spy: TriggerSpy = TriggerSpy()
    ) -> CaffeineController {
        let store = InMemorySettingsStore(settings: settings)
        return CaffeineController(
            assertions: AssertionManager(backing: backing, reason: "Test"),
            store: store,
            triggerFactory: { spy.makeTriggers(for: $0) }
        )
    }

    // MARK: - a) Reconfigure drains stale trigger reason (kịch bản fba522a)

    @Test("tắt app-trigger trong settings thì rút lý do app khỏi state, giữ nguyên charging, app vẫn active")
    func reconfigureDrainsStaleTriggerReason() {
        var settings = Settings()
        settings.appTriggerEnabled = true
        settings.triggerAppBundleIDs = ["com.example.app"]
        settings.chargingTriggerEnabled = true

        let spy = TriggerSpy()
        let controller = makeController(settings: settings, spy: spy)

        spy.appTrigger?.fire(.app("Ứng dụng mẫu"), active: true)
        spy.chargingTrigger?.fire(.charging, active: true)

        #expect(controller.state.triggerReasons == [.app("Ứng dụng mẫu"), .charging])
        #expect(controller.state.isActive)

        // Tắt app-trigger trong settings -> rebuildTriggers() chạy. Bộ trigger
        // cũ (cả app lẫn charging) bị dừng và MỌI lý do cũ bị xoá sạch trước,
        // không phân biệt lý do nào còn hợp lệ dưới cấu hình mới — đây chính
        // là điểm kịch bản fba522a từng hỏng (lý do app bị bỏ sót, kẹt lại
        // vĩnh viễn vì trước đó chỉ xoá khi bộ trigger mới rỗng).
        controller.settings.appTriggerEnabled = false

        // App-trigger không còn trong bộ trigger mới nên .app(...) bị rút
        // hẳn, không bao giờ quay lại.
        #expect(!controller.state.triggerReasons.contains(.app("Ứng dụng mẫu")))
        #expect(spy.appTrigger == nil)

        // Charging-trigger MỚI được tạo lại (settings vẫn bật nó). Trong
        // production, TriggerEngine.start() gọi refresh() ngay lập tức và
        // trigger thật (PowerSourceTrigger) sẽ tự phát lại .triggerFired nếu
        // điều kiện vẫn đúng — FakeTrigger không tự làm việc này nên ta mô
        // phỏng đúng bằng một lần fire thủ công đại diện cho refresh() đó.
        spy.chargingTrigger?.fire(.charging, active: true)

        #expect(controller.state.triggerReasons == [.charging])
        #expect(controller.state.isActive)
    }

    // MARK: - b) Create-failure forces inactive + sets lastFailure + releases all

    @Test("create thất bại giữa chừng thì buộc về inactive, ghi lastFailure, giải phóng hết cờ đã tạo")
    func createFailureForcesInactiveAndReleasesAll() {
        let backing = FakeBacking()
        backing.failingFlags = [.userIdle]
        var settings = Settings()
        settings.flags = [.display, .userIdle]

        let controller = makeController(settings: settings, backing: backing)

        controller.toggle()

        #expect(controller.state.isActive == false)
        #expect(controller.state.manual == false)
        #expect(controller.lastFailure != nil)
        // .display được tạo trước (id 1) rồi .userIdle ném lỗi -> rollback
        // giải phóng lại .display. Không cờ nào còn bị giữ.
        #expect(backing.calls == [.create(.display), .release(1)])
    }

    // MARK: - c) Timer expiry with manual still on stays active

    @Test("hẹn giờ hết hạn nhưng manual vẫn bật thì vẫn active")
    func timerExpiryWithManualStillOnStaysActive() {
        let controller = makeController()

        controller.send(.toggledManually(true))
        controller.send(.startedTimer(until: Date().addingTimeInterval(60)))
        #expect(controller.state.isActive)

        controller.send(.timerExpired)

        #expect(controller.state.timerEndsAt == nil)
        #expect(controller.state.manual)
        #expect(controller.state.isActive)
    }

    // MARK: - d) I2: Tắt là dứt khoát — không tự bật lại nếu điều kiện không
    // đổi, nhưng tái diễn (transition) thật thì bật lại. Xem doc comment ở
    // `CaffeineController.toggle()` cho ngữ nghĩa đầy đủ.

    @Test("Tắt xoá lý do trigger dứt khoát: không tự bật lại khi điều kiện không đổi, nhưng tái diễn thật thì bật lại")
    func stopIsDecisiveNoBounceBackButRecurrenceResumes() {
        var settings = Settings()
        settings.chargingTriggerEnabled = true
        let spy = TriggerSpy()
        let controller = makeController(settings: settings, spy: spy)

        spy.chargingTrigger?.fire(.charging, active: true)
        #expect(controller.state.isActive)
        #expect(controller.state.triggerReasons == [.charging])

        // Tắt dứt khoát: xoá manual + timer + mọi lý do trigger, kể cả lý do
        // đang đúng vật lý (vẫn cắm sạc).
        controller.toggle()
        #expect(controller.state.isActive == false)
        #expect(controller.state.triggerReasons.isEmpty)

        // "Không đổi": trigger thật (vd PowerSourceTrigger.refresh()) chỉ gọi
        // onChange khi điều kiện THỰC SỰ đổi (`guard charging != isCharging
        // else { return }`) — một status tick mà điều kiện y hệt lần trước
        // sẽ không phát sự kiện nào cả. FakeTrigger giờ mô phỏng đúng guard
        // đó (xem Fakes.swift): baseline của spy.chargingTrigger vẫn là
        // `true` từ lần fire đầu (stopAll ở trên không đụng tới nó, đúng như
        // trigger thật), nên gọi lại fire(.charging, active: true) — cùng
        // trạng thái, không có active:false chen giữa — bị guard nuốt và
        // KHÔNG forward tới controller. Đây là assertion thật: nếu guard bị
        // gỡ (hoặc stopAll ngừng xoá triggerReasons) thì bài test này sẽ
        // FAIL vì controller sẽ bật lại.
        spy.chargingTrigger?.fire(.charging, active: true)

        #expect(controller.state.isActive == false)
        #expect(controller.state.triggerReasons.isEmpty)

        // Tái diễn thật (rút sạc rồi cắm lại): trigger thật thấy chuyển tiếp
        // false→true và gọi onChange lần nữa. Mô phỏng đúng bằng một cặp
        // active:false rồi active:true.
        spy.chargingTrigger?.fire(.charging, active: false)
        spy.chargingTrigger?.fire(.charging, active: true)

        #expect(controller.state.isActive)
        #expect(controller.state.triggerReasons == [.charging])
    }
}

// MARK: - Hẹn giờ và trạng thái icon
//
// Phần đếm ngược không kiểm chứng được qua XCUITest (nhịp 1 Hz làm app không
// bao giờ "đứng yên" theo cách công cụ đó đòi hỏi), nên nó được phủ ở đây —
// tất định, không cần chờ đồng hồ thật chạy.

@Suite("CaffeineController — hẹn giờ")
@MainActor
struct CaffeineControllerTimerTests {

    private func makeController(settings: Settings = Settings()) -> CaffeineController {
        CaffeineController(
            assertions: AssertionManager(backing: FakeBacking(), reason: "Test"),
            store: InMemorySettingsStore(settings: settings),
            triggerFactory: { _ in [] }
        )
    }

    @Test("bắt đầu hẹn giờ thì đặt mốc kết thúc, bật active và vào chế độ đếm ngược")
    func startTimerEntersCountdown() {
        let controller = makeController()
        #expect(controller.isCountingDown == false)

        let before = Date()
        controller.startTimer(minutes: 15)

        let endsAt = try? #require(controller.state.timerEndsAt)
        #expect(controller.state.isActive)
        #expect(controller.isCountingDown)
        #expect(controller.timerTotalSeconds == 900)
        // Cho phép sai số nhỏ vì mốc được tính từ Date() bên trong.
        #expect(abs((endsAt ?? before).timeIntervalSince(before) - 900) < 2)
    }

    @Test("thời lượng ngoài khoảng bị kẹp — API public không giả định người gọi đã kiểm tra hộ")
    func startTimerClampsMinutes() {
        let controller = makeController()

        controller.startTimer(minutes: 100_000)
        #expect(controller.timerTotalSeconds == TimeInterval(480 * 60))

        controller.startTimer(minutes: -5)
        #expect(controller.timerTotalSeconds == TimeInterval(1 * 60))
    }

    @Test("mực cà phê vơi theo thời gian, đầy lúc bắt đầu và cạn lúc hết")
    func iconProgressDrainsOverTime() throws {
        let controller = makeController()
        controller.startTimer(minutes: 60)
        let endsAt = try #require(controller.state.timerEndsAt)
        let startedAt = endsAt.addingTimeInterval(-3_600)

        let full = try #require(controller.iconState(at: startedAt).progress)
        let half = try #require(controller.iconState(at: startedAt.addingTimeInterval(1_800)).progress)
        let empty = try #require(controller.iconState(at: endsAt).progress)

        #expect(full == 1.0)
        #expect(abs(half - 0.5) < 0.05)
        #expect(empty == 0.0)

        // Quá hạn thì kẹp ở cạn, không âm.
        #expect(controller.iconState(at: endsAt.addingTimeInterval(600)).progress == 0.0)
    }

    @Test("bật không giới hạn thì icon không còn mực vơi dần để mà vẽ")
    func indefiniteHasNoProgress() {
        let controller = makeController()
        controller.startIndefinite()

        #expect(controller.state.isActive)
        #expect(controller.isCountingDown == false)
        #expect(controller.iconState(at: .now).progress == nil)
        // Mốc tổng phải được xoá, nếu không lần vẽ sau còn chia cho số cũ.
        #expect(controller.timerTotalSeconds == 0)
    }

    @Test("chuyển từ hẹn giờ sang không giới hạn thì xoá sạch mốc hẹn giờ cũ")
    func indefiniteClearsRunningTimer() {
        let controller = makeController()
        controller.startTimer(minutes: 30)
        #expect(controller.isCountingDown)

        controller.startIndefinite()

        #expect(controller.state.timerEndsAt == nil)
        #expect(controller.isCountingDown == false)
        #expect(controller.timerTotalSeconds == 0)
    }

    @Test("tắt thì mọi thứ về không: không active, không đếm ngược, không mốc")
    func stopClearsEverything() {
        let controller = makeController()
        controller.startTimer(minutes: 30)

        controller.stop()

        #expect(controller.state.isActive == false)
        #expect(controller.state.timerEndsAt == nil)
        #expect(controller.isCountingDown == false)
        #expect(controller.timerTotalSeconds == 0)
        #expect(controller.iconState(at: .now).isActive == false)
    }

    @Test("trạng thái lỗi được phản ánh vào icon để người dùng thấy ngay trên thanh menu")
    func failureShowsInIconState() {
        let backing = FakeBacking()
        backing.failingFlags = [.system]
        let controller = CaffeineController(
            assertions: AssertionManager(backing: backing, reason: "Test"),
            store: InMemorySettingsStore(settings: Settings()),
            triggerFactory: { _ in [] }
        )

        controller.startIndefinite()

        #expect(controller.lastFailure != nil)
        #expect(controller.iconState(at: .now).hasError)
    }
}
