import Foundation
import IOKit.ps

/// Bật khi máy đang chạy bằng nguồn AC.
@MainActor
public final class PowerSourceTrigger: Trigger {
    public var onChange: (@MainActor (TriggerReason, Bool) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var isCharging = false

    public init() {}

    public func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let trigger = Unmanaged<PowerSourceTrigger>
                .fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { trigger.refresh() }
        }, context)?.takeRetainedValue() else { return }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        refresh()
    }

    public func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            self.runLoopSource = nil
        }
        if isCharging {
            isCharging = false
            onChange?(.charging, false)
        }
    }

    private func refresh() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return }
        let type = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as String?
        let charging = (type == kIOPMACPowerKey)

        // Chỉ báo khi THỰC SỰ đổi. Đây là nền tảng cho ngữ nghĩa "Tắt là dứt
        // khoát" ở CaffeineController.toggle(): sau khi người dùng bấm Tắt
        // trong lúc đang sạc, baseline `isCharging` ở đây vẫn giữ `true`
        // (không bị reset bởi stopAll), nên một thông báo nguồn điện tới sau
        // đó mà vẫn đang sạc sẽ KHÔNG gọi onChange — không tự bật lại. Chỉ
        // một chuyển tiếp thật (rút sạc rồi cắm lại, false→true) mới phát lại
        // .triggerFired. Không được xoá guard này hay reset isCharging từ
        // bên ngoài để "sửa" cho nó báo lại mỗi lần — làm vậy sẽ phá vỡ tính
        // dứt khoát của nút Tắt.
        guard charging != isCharging else { return }
        isCharging = charging
        onChange?(.charging, charging)
    }
}
