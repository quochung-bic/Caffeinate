import AppKit

/// Fires while any app from the list is running.
@MainActor
public final class AppRunningTrigger: Trigger {
    public var onChange: (@MainActor (TriggerReason, Bool) -> Void)?

    private let bundleIDs: [String]
    private var observers: [NSObjectProtocol] = []
    /// bundleID → the display name already reported, so the matching
    /// reason can be cleared later.
    private var reported: [String: String] = [:]

    public init(bundleIDs: [String]) {
        self.bundleIDs = bundleIDs
    }

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            let observer = center.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(observer)
        }
        refresh()
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        for (_, name) in reported {
            onChange?(.app(name), false)
        }
        reported.removeAll()
    }

    private func refresh() {
        let running = NSWorkspace.shared.runningApplications
        var nowRunning: [String: String] = [:]
        for app in running {
            guard let id = app.bundleIdentifier, bundleIDs.contains(id) else { continue }
            nowRunning[id] = app.localizedName ?? id
        }

        for (id, name) in nowRunning where reported[id] == nil {
            reported[id] = name
            onChange?(.app(name), true)
        }
        for (id, name) in reported where nowRunning[id] == nil {
            reported.removeValue(forKey: id)
            onChange?(.app(name), false)
        }
    }
}
