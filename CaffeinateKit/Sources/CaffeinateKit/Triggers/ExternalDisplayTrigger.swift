import AppKit

/// Bật khi có từ hai màn hình trở lên.
@MainActor
public final class ExternalDisplayTrigger: Trigger {
    public var onChange: (@MainActor (TriggerReason, Bool) -> Void)?

    private var observer: NSObjectProtocol?
    private var hasExternal = false

    public init() {}

    public func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    public func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        if hasExternal {
            hasExternal = false
            onChange?(.externalDisplay, false)
        }
    }

    private func refresh() {
        let external = NSScreen.screens.count > 1
        guard external != hasExternal else { return }
        hasExternal = external
        onChange?(.externalDisplay, external)
    }
}
