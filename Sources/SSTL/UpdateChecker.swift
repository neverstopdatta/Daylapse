import AppKit

// Compares this build with the latest GitHub release and points to its page; nothing is downloaded or installed.
enum UpdateChecker {
    static let repositoryURL = URL(string: "https://github.com/neverstopdatta/Screenshots-Timelapse")!
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/neverstopdatta/Screenshots-Timelapse/releases/latest")!
    private static let lastCheckKey = "lastUpdateCheck"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
    }

    private enum CheckError: LocalizedError {
        case noReleases
        var errorDescription: String? { "No releases have been published yet." }
    }

    // Automatic checks run at most once a day.
    @MainActor static func checkIfDue() {
        guard SettingsStore.shared.settings.checkForUpdates else { return }
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= 86_400 else { return }
        check(userInitiated: false)
    }

    // A manual check always reports back; an automatic one speaks only when there is something new.
    @MainActor static func check(userInitiated: Bool) {
        // Stamped on every attempt so a failing automatic check waits a day too.
        UserDefaults.standard.set(Date(), forKey: lastCheckKey)
        Task {
            do {
                let release = try await latestRelease()
                let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if isNewer(latest, than: currentVersion) {
                    offer(latest, page: release.html_url)
                } else if userInitiated {
                    show("You're up to date", "Version \(currentVersion) is the latest.")
                }
            } catch {
                SSTLLog.write("Update check failed: \(error.localizedDescription)")
                if userInitiated { show("Couldn't check for updates", error.localizedDescription) }
            }
        }
    }

    private static func latestRelease() async throws -> Release {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { throw CheckError.noReleases }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // Numeric, part by part, so 1.10 is newer than 1.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    @MainActor private static func offer(_ version: String, page: URL) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Version \(version) is available"
        alert.informativeText = "You have version \(currentVersion). The release page has the download and what changed."
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
    }

    @MainActor private static func show(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}
