import AppKit
import ScreenCaptureKit

@MainActor
final class AppRules {
    struct Frontmost {
        let bundleID: String?
        let name: String
    }

    enum Pause: Equatable {
        case notAllowed, locked, asleep, lowDisk, idle

        var statusText: String {
            switch self {
            case .notAllowed: "⊘ Not allowed"
            case .locked: "⏸ Locked"
            case .asleep: "⏸ Asleep"
            case .lowDisk: "⏸ Low disk"
            case .idle: "⏸ Idle"
            }
        }
    }

    private let settings: SettingsStore
    private(set) var lastExternalFrontmost: Frontmost?
    private var observer: NSObjectProtocol?
    private var lastLoggedOwners: Set<String> = []

    init(settings: SettingsStore) {
        self.settings = settings
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.recordFrontmost(app) }
        }
        refreshFrontmost()
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func pauseReason() -> Pause? {
        refreshFrontmost()
        guard let frontmost = lastExternalFrontmost, let bundleID = frontmost.bundleID else {
            return .notAllowed
        }
        let current = settings.settings
        if current.appMode == "allow" {
            guard !current.allowedApps.isEmpty,
                  current.allowedApps.contains(where: { $0.bundleID == bundleID }) else {
                return .notAllowed
            }
        } else if current.blockedApps.contains(where: { $0.bundleID == bundleID }) {
            return .notAllowed
        }
        return nil
    }

    func menuTitle() -> String? {
        refreshFrontmost()
        guard let frontmost = lastExternalFrontmost, let bundleID = frontmost.bundleID else { return nil }
        let current = settings.settings
        if current.appMode == "allow" {
            let isAllowed = current.allowedApps.contains { $0.bundleID == bundleID }
            return isAllowed ? "Remove \(quoted(frontmost.name))" : "Allow \(quoted(frontmost.name))"
        }
        let isBlocked = current.blockedApps.contains { $0.bundleID == bundleID }
        return isBlocked ? "Unblock \(quoted(frontmost.name))" : "Block \(quoted(frontmost.name))"
    }

    func toggleCurrentRule() throws {
        refreshFrontmost()
        guard let frontmost = lastExternalFrontmost, let bundleID = frontmost.bundleID else { return }
        var current = settings.settings
        let entry = AppRuleEntry(bundleID: bundleID, name: frontmost.name)
        if current.appMode == "allow" {
            if current.allowedApps.contains(where: { $0.bundleID == bundleID }) {
                current.allowedApps.removeAll { $0.bundleID == bundleID }
            } else {
                current.allowedApps.append(entry)
            }
        } else if current.blockedApps.contains(where: { $0.bundleID == bundleID }) {
            current.blockedApps.removeAll { $0.bundleID == bundleID }
        } else {
            current.blockedApps.append(entry)
        }
        try settings.save(current)
    }

    func makeFilter(display: SCDisplay, content: SCShareableContent, settings snapshot: SSTLSettings) -> SCContentFilter? {
        logWindowOwners(content)
        let finderID = "com.apple.finder"
        let finderWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == finderID }
        let normalFinderWindows = finderWindows.filter { $0.windowLayer == 0 }

        if snapshot.appMode == "allow" {
            guard !snapshot.allowedApps.isEmpty else { return nil }
            let allowedIDs = Set(snapshot.allowedApps.map(\.bundleID))
            guard allowedIDs.allSatisfy({ id in content.applications.contains(where: { $0.bundleIdentifier == id }) }) else {
                return nil
            }
            // Including apps never captures the desktop icons, so with icons on, hide every window
            // that is not allowed instead. Hiding by window leaves wallpaper and icons visible.
            if snapshot.showDesktopIcons {
                let shown = allowedIDs
                    .union(snapshot.showNotifications ? [SSTLSettings.notificationBundleID] : [])
                    .union(snapshot.showWallpaper ? [SSTLSettings.wallpaperBundleID] : [])
                let hidden = content.windows.filter { window in
                    guard let id = window.owningApplication?.bundleIdentifier else { return true }
                    if shown.contains(id) { return false }
                    return !(id == finderID && window.windowLayer < 0)
                }
                return SCContentFilter(display: display, excludingWindows: hidden)
            }
            var includedIDs = allowedIDs
            if snapshot.showNotifications { includedIDs.insert(SSTLSettings.notificationBundleID) }
            if snapshot.showWallpaper { includedIDs.insert(SSTLSettings.wallpaperBundleID) }
            let included = content.applications.filter { includedIDs.contains($0.bundleIdentifier) }
            return SCContentFilter(display: display, including: included, exceptingWindows: [])
        }

        var excludedIDs = Set(snapshot.blockedApps.map(\.bundleID))
        if let ownBundleID = Bundle.main.bundleIdentifier { excludedIDs.insert(ownBundleID) }
        if !snapshot.showNotifications { excludedIDs.insert(SSTLSettings.notificationBundleID) }

        // Excluding the wallpaper app does not remove the wallpaper, so hide it by window instead.
        // That is the only way the background colour can show through.
        if !snapshot.showWallpaper {
            let hidden = content.windows.filter { window in
                let id = window.owningApplication?.bundleIdentifier ?? ""
                if excludedIDs.contains(id) || isWallpaperWindow(window) { return true }
                return !snapshot.showDesktopIcons && id == finderID && window.windowLayer < 0
            }
            return SCContentFilter(display: display, excludingWindows: hidden)
        }

        // Hiding Finder also hides the desktop icons, so keep its normal windows.
        var keptWindows: [SCWindow] = []
        if !snapshot.showDesktopIcons, !excludedIDs.contains(finderID) {
            excludedIDs.insert(finderID)
            keptWindows = normalFinderWindows
        }
        let excluded = content.applications.filter { excludedIDs.contains($0.bundleIdentifier) }
        return SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: keptWindows)
    }

    // The picture is drawn by three windows: the wallpaper agent's, a Dock window titled
    // "Wallpaper-…", and an ownerless "Desktop" backing. All three must go for the fill to show.
    private func isWallpaperWindow(_ window: SCWindow) -> Bool {
        let id = window.owningApplication?.bundleIdentifier ?? ""
        switch id {
        case SSTLSettings.wallpaperBundleID: return true
        case "com.apple.dock": return (window.title ?? "").hasPrefix("Wallpaper")
        case "": return window.title == "Desktop"
        default: return false
        }
    }

    // M8 experiment: shows which apps own on-screen windows, to confirm who draws notifications.
    private func logWindowOwners(_ content: SCShareableContent) {
        let owners = Set(content.windows.compactMap { $0.owningApplication?.bundleIdentifier })
        guard owners != lastLoggedOwners else { return }
        lastLoggedOwners = owners
        SSTLLog.write("Window owners: \(owners.sorted().joined(separator: ", "))")
    }

    func frontmostStillAllowsCapture(settings snapshot: SSTLSettings) -> Bool {
        guard settings.settings == snapshot else { return false }
        return pauseReason() == nil
    }

    private func refreshFrontmost() {
        if let app = NSWorkspace.shared.frontmostApplication {
            recordFrontmost(app)
        } else if lastExternalFrontmost != nil {
            lastExternalFrontmost = nil
            SSTLLog.write("Frontmost app unavailable")
        }
    }

    private func recordFrontmost(_ app: NSRunningApplication) {
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        let frontmost = Frontmost(bundleID: app.bundleIdentifier, name: app.localizedName ?? app.bundleIdentifier ?? "Unknown")
        guard lastExternalFrontmost?.bundleID != frontmost.bundleID || lastExternalFrontmost?.name != frontmost.name else { return }
        lastExternalFrontmost = frontmost
        SSTLLog.write("Frontmost app: \(frontmost.name) (\(frontmost.bundleID ?? "unknown bundle ID"))")
    }

    private func quoted(_ name: String) -> String { "\"\(name)\"" }
}
