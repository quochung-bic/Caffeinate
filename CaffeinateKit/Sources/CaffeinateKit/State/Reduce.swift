/// Hàm thuần tuý: trạng thái mới chỉ phụ thuộc trạng thái cũ và sự kiện.
/// Không I/O, không thời gian hệ thống — mọi mốc thời gian đi vào qua sự kiện.
public func reduce(_ state: CaffeineState, _ event: CaffeineEvent) -> CaffeineState {
    var next = state

    switch event {
    case .toggledManually(let on):
        next.manual = on
        // Bật thủ công NGHĨA LÀ "không giới hạn", nên nó phải xoá hẹn giờ đang
        // chạy: để timerEndsAt sót lại thì UI vẫn vẽ vòng đếm ngược (thông tin
        // sai), và nếu sau đó tắt thủ công thì cái hẹn giờ cũ sẽ bất ngờ sống
        // lại. Tắt thủ công thì không đụng tới hẹn giờ — nó là nguồn độc lập.
        if on { next.timerEndsAt = nil }

    case .startedTimer(let until):
        next.timerEndsAt = until

    case .timerExpired:
        next.timerEndsAt = nil

    case .triggerFired(let reason):
        next.triggerReasons.insert(reason)

    case .triggerCleared(let reason):
        next.triggerReasons.remove(reason)

    case .flagsChanged(let flags):
        next.flags = flags

    case .stopAll:
        next.manual = false
        next.timerEndsAt = nil
        next.triggerReasons.removeAll()
    }

    return next
}
