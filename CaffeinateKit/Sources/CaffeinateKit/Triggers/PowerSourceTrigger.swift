import Foundation
import IOKit.ps

/// Fires while the Mac is running on AC power.
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

        // Report only on a REAL change. This underpins the "Stop is decisive"
        // semantics in CaffeineController.toggle(): after the user presses Stop
        // while charging, the `isCharging` baseline here stays `true` (stopAll
        // does not reset it), so a later power notification that still says
        // "charging" does NOT call onChange — nothing switches itself back on.
        // Only a genuine transition (unplug, then plug back in, false→true)
        // emits .triggerFired again. Do not delete this guard or reset
        // isCharging from outside to "fix" it into reporting every time — that
        // would destroy the decisiveness of the Stop button.
        guard charging != isCharging else { return }
        isCharging = charging
        onChange?(.charging, charging)
    }
}
