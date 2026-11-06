import AppKit

// Tracks locked, asleep, idle and low-disk state for the pause reasons.
@MainActor
final class SystemState {
    private let settings: SettingsStore
    private var isLocked = false
    private var isAsleep = false
    private var lastDiskCheck = Date.distantPast
    private var isLowDisk = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(settings: SettingsStore) {
        self.settings = settings
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(distributed, "com.apple.screenIsLocked") { $0.isLocked = true }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.isLocked = false }
        observe(workspace, NSWorkspace.willSleepNotification.rawValue) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue) { $0.isAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification.rawValue) { $0.isAsleep = false }
        observe(workspace, NSWorkspace.screensDidWakeNotification.rawValue) { $0.isAsleep = false }
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    func pauseReason() -> AppRules.Pause? {
        let current = settings.settings
        if current.pauseWhenLocked, isLocked { return .locked }
        if isAsleep { return .asleep }
        if lowDisk(minGB: current.minFreeSpaceGB) { return .lowDisk }
        if current.pauseWhenIdleSeconds > 0, idleSeconds() >= Double(current.pauseWhenIdleSeconds) { return .idle }
        return nil
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ update: @escaping @MainActor (SystemState) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                update(self)
                DaylapseLog.write("System state: \(name)")
            }
        }
        observers.append((center, token))
    }

    private func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    // Checked once a minute, not every tick.
    private func lowDisk(minGB: Int) -> Bool {
        if Date().timeIntervalSince(lastDiskCheck) >= 60 {
            lastDiskCheck = Date()
            let folder = Storage.screenshotsFolder
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let free = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage
            isLowDisk = free.map { $0 < Int64(minGB) * 1_000_000_000 } ?? false
        }
        return isLowDisk
    }
}
