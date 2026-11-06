import AppKit
import ScreenCaptureKit

@MainActor
final class AppRules {
    struct Frontmost {
        let bundleID: String?
        let name: String
    }

    enum Pause: Equatable {
        case blocked(String)
        case notAllowed

        var statusText: String {
            switch self {
            case .blocked(let name): "⏸ \(String(name.prefix(14)))"
            case .notAllowed: "⏸ Not allowed"
            }
        }
    }

    private let settings: SettingsStore
    private(set) var lastExternalFrontmost: Frontmost?
    private var observer: NSObjectProtocol?

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
        } else if let blocked = current.blockedApps.first(where: { $0.bundleID == bundleID }) {
            return .blocked(blocked.name)
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

    func makeFilter(display: SCDisplay, content: SCShareableContent, settings snapshot: DaylapseSettings) -> SCContentFilter? {
        let ownBundleID = Bundle.main.bundleIdentifier
        if snapshot.appMode == "allow" {
            guard !snapshot.allowedApps.isEmpty else { return nil }
            let allowedIDs = Set(snapshot.allowedApps.map(\.bundleID))
            guard allowedIDs.allSatisfy({ id in content.applications.contains(where: { $0.bundleIdentifier == id }) }) else {
                return nil
            }
            let includedApplications = content.applications.filter { allowedIDs.contains($0.bundleIdentifier) }
            return SCContentFilter(display: display, including: includedApplications, exceptingWindows: [])
        }

        let excludedIDs = Set(snapshot.blockedApps.map(\.bundleID)).union(Set(ownBundleID.map { [$0] } ?? []))
        let excludedApplications = content.applications.filter { app in
            excludedIDs.contains(app.bundleIdentifier)
        }
        return SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
    }

    func frontmostStillAllowsCapture(settings snapshot: DaylapseSettings) -> Bool {
        guard settings.settings == snapshot else { return false }
        return pauseReason() == nil
    }

    private func refreshFrontmost() {
        if let app = NSWorkspace.shared.frontmostApplication {
            recordFrontmost(app)
        } else {
            lastExternalFrontmost = nil
        }
    }

    private func recordFrontmost(_ app: NSRunningApplication) {
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        lastExternalFrontmost = Frontmost(bundleID: app.bundleIdentifier, name: app.localizedName ?? app.bundleIdentifier ?? "Unknown")
    }

    private func quoted(_ name: String) -> String { "\"\(name)\"" }
}
