import Foundation
import Observation

struct AppRuleEntry: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

struct ShortcutSettings: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = ShortcutSettings(keyCode: 1, carbonModifiers: 2560)
}

struct SSTLSettings: Codable, Equatable {
    static let wallpaperBundleID = "com.apple.wallpaper.agent"
    static let notificationBundleID = "com.apple.notificationcenterui"

    var intervalSeconds: Int
    var resumeCountdown: Bool
    var captureOnStart: Bool
    var showPointer: Bool
    var pauseWhenIdleSeconds: Int
    var pauseWhenLocked: Bool
    var pauseWhenMenuOpen: Bool
    var displays: String
    var halfSizeOnRetina: Bool
    var jpegQuality: Double
    var imageFormat: String
    var appMode: String
    var blockedApps: [AppRuleEntry]
    var allowedApps: [AppRuleEntry]
    var showNotifications: Bool
    var showDesktopIcons: Bool
    var showWallpaper: Bool
    var backgroundHex: String
    var rootPath: String
    var activeProject: String
    var deleteAfterDays: Int
    var deletePermanently: Bool
    var minFreeSpaceGB: Int
    var exportFPS: Int
    var checkForUpdates: Bool
    var notifyOnToggle: Bool
    var soundOnToggle: Bool
    var startSound: String
    var stopSound: String
    var exportFormat: String
    var shortcut: ShortcutSettings

    static let defaults = SSTLSettings(
        intervalSeconds: 30,
        resumeCountdown: false,
        captureOnStart: true,
        showPointer: false,
        pauseWhenIdleSeconds: 60,
        pauseWhenLocked: true,
        pauseWhenMenuOpen: false,
        displays: "all",
        halfSizeOnRetina: false,
        jpegQuality: 0.8,
        imageFormat: "jpeg",
        appMode: "block",
        blockedApps: [],
        allowedApps: [],
        showNotifications: false,
        showDesktopIcons: false,
        showWallpaper: true,
        backgroundHex: "#000000",
        rootPath: Storage.defaultRootPath,
        activeProject: Projects.defaultName,
        deleteAfterDays: 0,
        deletePermanently: false,
        minFreeSpaceGB: 5,
        exportFPS: 12,
        checkForUpdates: true,
        notifyOnToggle: false,
        soundOnToggle: false,
        startSound: "Glass",
        stopSound: "Funk",
        exportFormat: "mp4",
        shortcut: .default
    )

    private enum CodingKeys: String, CodingKey {
        case intervalSeconds, resumeCountdown, captureOnStart, showPointer, pauseWhenIdleSeconds, pauseWhenLocked, pauseWhenMenuOpen, displays
        case halfSizeOnRetina, jpegQuality, imageFormat, appMode, blockedApps, allowedApps
        case showNotifications, showDesktopIcons, showWallpaper, backgroundHex, hideNotifications, hideDesktopIcons
        case rootPath, activeProject, deleteAfterDays
        case deletePermanently, minFreeSpaceGB, exportFPS, checkForUpdates, notifyOnToggle, soundOnToggle, startSound, stopSound, exportFormat, shortcut
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(intervalSeconds, forKey: .intervalSeconds)
        try c.encode(resumeCountdown, forKey: .resumeCountdown)
        try c.encode(captureOnStart, forKey: .captureOnStart)
        try c.encode(showPointer, forKey: .showPointer)
        try c.encode(pauseWhenIdleSeconds, forKey: .pauseWhenIdleSeconds)
        try c.encode(pauseWhenLocked, forKey: .pauseWhenLocked)
        try c.encode(pauseWhenMenuOpen, forKey: .pauseWhenMenuOpen)
        try c.encode(displays, forKey: .displays)
        try c.encode(halfSizeOnRetina, forKey: .halfSizeOnRetina)
        try c.encode(jpegQuality, forKey: .jpegQuality)
        try c.encode(imageFormat, forKey: .imageFormat)
        try c.encode(appMode, forKey: .appMode)
        try c.encode(blockedApps, forKey: .blockedApps)
        try c.encode(allowedApps, forKey: .allowedApps)
        try c.encode(showNotifications, forKey: .showNotifications)
        try c.encode(showDesktopIcons, forKey: .showDesktopIcons)
        try c.encode(showWallpaper, forKey: .showWallpaper)
        try c.encode(backgroundHex, forKey: .backgroundHex)
        try c.encode(rootPath, forKey: .rootPath)
        try c.encode(activeProject, forKey: .activeProject)
        try c.encode(deleteAfterDays, forKey: .deleteAfterDays)
        try c.encode(deletePermanently, forKey: .deletePermanently)
        try c.encode(minFreeSpaceGB, forKey: .minFreeSpaceGB)
        try c.encode(exportFPS, forKey: .exportFPS)
        try c.encode(checkForUpdates, forKey: .checkForUpdates)
        try c.encode(notifyOnToggle, forKey: .notifyOnToggle)
        try c.encode(soundOnToggle, forKey: .soundOnToggle)
        try c.encode(startSound, forKey: .startSound)
        try c.encode(stopSound, forKey: .stopSound)
        try c.encode(exportFormat, forKey: .exportFormat)
        try c.encode(shortcut, forKey: .shortcut)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        intervalSeconds = try values.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? defaults.intervalSeconds
        resumeCountdown = try values.decodeIfPresent(Bool.self, forKey: .resumeCountdown) ?? defaults.resumeCountdown
        captureOnStart = try values.decodeIfPresent(Bool.self, forKey: .captureOnStart) ?? defaults.captureOnStart
        showPointer = try values.decodeIfPresent(Bool.self, forKey: .showPointer) ?? defaults.showPointer
        pauseWhenIdleSeconds = try values.decodeIfPresent(Int.self, forKey: .pauseWhenIdleSeconds) ?? defaults.pauseWhenIdleSeconds
        pauseWhenLocked = try values.decodeIfPresent(Bool.self, forKey: .pauseWhenLocked) ?? defaults.pauseWhenLocked
        pauseWhenMenuOpen = try values.decodeIfPresent(Bool.self, forKey: .pauseWhenMenuOpen) ?? defaults.pauseWhenMenuOpen
        displays = try values.decodeIfPresent(String.self, forKey: .displays) ?? defaults.displays
        halfSizeOnRetina = try values.decodeIfPresent(Bool.self, forKey: .halfSizeOnRetina) ?? defaults.halfSizeOnRetina
        jpegQuality = try values.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? defaults.jpegQuality
        imageFormat = try values.decodeIfPresent(String.self, forKey: .imageFormat) ?? defaults.imageFormat
        appMode = try values.decodeIfPresent(String.self, forKey: .appMode) ?? defaults.appMode
        blockedApps = try values.decodeIfPresent([AppRuleEntry].self, forKey: .blockedApps) ?? defaults.blockedApps
        allowedApps = try values.decodeIfPresent([AppRuleEntry].self, forKey: .allowedApps) ?? defaults.allowedApps
        // The old hide* keys are read once so existing settings files keep their meaning.
        let legacyHideNotifications = try values.decodeIfPresent(Bool.self, forKey: .hideNotifications)
        let legacyHideIcons = try values.decodeIfPresent(Bool.self, forKey: .hideDesktopIcons)
        showNotifications = try values.decodeIfPresent(Bool.self, forKey: .showNotifications)
            ?? legacyHideNotifications.map { !$0 } ?? defaults.showNotifications
        showDesktopIcons = try values.decodeIfPresent(Bool.self, forKey: .showDesktopIcons)
            ?? legacyHideIcons.map { !$0 } ?? defaults.showDesktopIcons
        showWallpaper = try values.decodeIfPresent(Bool.self, forKey: .showWallpaper) ?? defaults.showWallpaper
        backgroundHex = try values.decodeIfPresent(String.self, forKey: .backgroundHex) ?? defaults.backgroundHex
        rootPath = try values.decodeIfPresent(String.self, forKey: .rootPath) ?? defaults.rootPath
        activeProject = try values.decodeIfPresent(String.self, forKey: .activeProject) ?? defaults.activeProject
        deleteAfterDays = try values.decodeIfPresent(Int.self, forKey: .deleteAfterDays) ?? defaults.deleteAfterDays
        deletePermanently = try values.decodeIfPresent(Bool.self, forKey: .deletePermanently) ?? defaults.deletePermanently
        minFreeSpaceGB = try values.decodeIfPresent(Int.self, forKey: .minFreeSpaceGB) ?? defaults.minFreeSpaceGB
        exportFPS = try values.decodeIfPresent(Int.self, forKey: .exportFPS) ?? defaults.exportFPS
        checkForUpdates = try values.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? defaults.checkForUpdates
        notifyOnToggle = try values.decodeIfPresent(Bool.self, forKey: .notifyOnToggle) ?? defaults.notifyOnToggle
        soundOnToggle = try values.decodeIfPresent(Bool.self, forKey: .soundOnToggle) ?? defaults.soundOnToggle
        startSound = try values.decodeIfPresent(String.self, forKey: .startSound) ?? defaults.startSound
        stopSound = try values.decodeIfPresent(String.self, forKey: .stopSound) ?? defaults.stopSound
        exportFormat = try values.decodeIfPresent(String.self, forKey: .exportFormat) ?? defaults.exportFormat
        shortcut = try values.decodeIfPresent(ShortcutSettings.self, forKey: .shortcut) ?? defaults.shortcut
    }

    init(
        intervalSeconds: Int, resumeCountdown: Bool, captureOnStart: Bool, showPointer: Bool, pauseWhenIdleSeconds: Int, pauseWhenLocked: Bool,
        pauseWhenMenuOpen: Bool, displays: String, halfSizeOnRetina: Bool, jpegQuality: Double, imageFormat: String, appMode: String,
        blockedApps: [AppRuleEntry], allowedApps: [AppRuleEntry], showNotifications: Bool,
        showDesktopIcons: Bool, showWallpaper: Bool, backgroundHex: String, rootPath: String, activeProject: String, deleteAfterDays: Int, deletePermanently: Bool,
        minFreeSpaceGB: Int, exportFPS: Int, checkForUpdates: Bool, notifyOnToggle: Bool, soundOnToggle: Bool, startSound: String, stopSound: String, exportFormat: String, shortcut: ShortcutSettings
    ) {
        self.intervalSeconds = intervalSeconds
        self.resumeCountdown = resumeCountdown
        self.captureOnStart = captureOnStart
        self.showPointer = showPointer
        self.pauseWhenIdleSeconds = pauseWhenIdleSeconds
        self.pauseWhenLocked = pauseWhenLocked
        self.pauseWhenMenuOpen = pauseWhenMenuOpen
        self.displays = displays
        self.halfSizeOnRetina = halfSizeOnRetina
        self.jpegQuality = jpegQuality
        self.imageFormat = imageFormat
        self.appMode = appMode
        self.blockedApps = blockedApps
        self.allowedApps = allowedApps
        self.showNotifications = showNotifications
        self.showDesktopIcons = showDesktopIcons
        self.showWallpaper = showWallpaper
        self.backgroundHex = backgroundHex
        self.rootPath = rootPath
        self.activeProject = activeProject
        self.deleteAfterDays = deleteAfterDays
        self.deletePermanently = deletePermanently
        self.minFreeSpaceGB = minFreeSpaceGB
        self.exportFPS = exportFPS
        self.checkForUpdates = checkForUpdates
        self.notifyOnToggle = notifyOnToggle
        self.soundOnToggle = soundOnToggle
        self.startSound = startSound
        self.stopSound = stopSound
        self.exportFormat = exportFormat
        self.shortcut = shortcut
    }
}

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private(set) var settings: SSTLSettings
    // The project folders in the root, kept current by `rootWatcher`.
    private(set) var projects: [String] = []
    private let fileURL: URL
    // The folders seen on disk last time (nil before the first read), to tell a vanished project from one not yet created.
    @ObservationIgnored private var diskProjects: [String]?
    @ObservationIgnored private var rootWatcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedRoot = ""

    private init() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Screenshots Timelapse", isDirectory: true)
        fileURL = support.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(SSTLSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .defaults
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let backupURL = fileURL.appendingPathExtension("bak")
                do {
                    if !FileManager.default.fileExists(atPath: backupURL.path) {
                        try FileManager.default.moveItem(at: fileURL, to: backupURL)
                    }
                    SSTLLog.write("Settings could not be decoded; using defaults")
                } catch {
                    SSTLLog.write("Could not back up invalid settings: \(error.localizedDescription)")
                }
            }
        }
        reconcileProjects(&settings)
        Storage.folderPath = settings.folderPath
        watchRoot()
    }

    func save(_ saved: SSTLSettings) throws {
        var newSettings = saved
        reconcileProjects(&newSettings)
        Storage.folderPath = newSettings.folderPath
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(newSettings)
        try data.write(to: fileURL, options: .atomic)
        settings = newSettings
        watchRoot()
    }

    // Reads the project folders from disk and keeps the active one valid. Nothing is created here:
    // the active project's folder appears with the first screenshot, so until then it is listed without one.
    private func reconcileProjects(_ s: inout SSTLSettings) {
        let names = Projects.names(in: s.rootURL)
        // A missing root (renamed away, or a disk not mounted) keeps the selection for when it comes back.
        let rootExists = FileManager.default.fileExists(atPath: s.rootURL.path)
        if rootExists, !names.contains(s.activeProject), diskProjects?.contains(s.activeProject) ?? true {
            // A single folder swapped for another is a rename in Finder, so the project follows it.
            let previous = diskProjects ?? []
            let added = names.filter { !previous.contains($0) }
            let removed = previous.filter { !names.contains($0) }
            s.activeProject = removed == [s.activeProject] && added.count == 1 ? added[0] : Projects.fallback(in: names)
        }
        diskProjects = names
        let listed = names.contains(s.activeProject)
            ? names
            : (names + [s.activeProject]).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        if listed != projects { projects = listed }
    }

    // Watches the root so folders added, renamed or deleted in Finder update the project list.
    private func watchRoot() {
        guard rootWatcher == nil || watchedRoot != settings.rootPath else { return }
        rootWatcher?.cancel()
        rootWatcher = nil
        watchedRoot = settings.rootPath
        // While the root is missing, its parent is watched instead so the root coming back is noticed.
        var descriptor = open(settings.rootURL.path, O_EVTONLY)
        let watchingParent = descriptor < 0
        if watchingParent { descriptor = open(settings.rootURL.deletingLastPathComponent().path, O_EVTONLY) }
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            MainActor.assumeIsolated {
                guard let self, let source else { return }
                // Any change beside a missing root, or the root itself moving away, starts the watch over.
                if watchingParent || !source.data.isDisjoint(with: [.rename, .delete]) {
                    let moved = !watchingParent && source.data.contains(.rename) ? Self.currentPath(of: descriptor) : nil
                    source.cancel()
                    self.rootWatcher = nil
                    // A renamed or moved root is followed (saving watches the new path), but not into the Trash.
                    if let moved, !moved.contains("/.Trash/") {
                        var updated = self.settings
                        updated.rootPath = (moved as NSString).abbreviatingWithTildeInPath
                        do {
                            try self.save(updated)
                        } catch {
                            SSTLLog.write("Could not save settings: \(error.localizedDescription)")
                        }
                    }
                }
                self.syncWithDisk()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        rootWatcher = source
    }

    // Where an open folder is now, even after it was renamed or moved.
    private static func currentPath(of descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        return String(cString: buffer)
    }

    // Also called when the menu opens or Settings comes forward, as a safety net for missed events.
    func syncWithDisk() {
        var updated = settings
        reconcileProjects(&updated)
        if updated != settings {
            do {
                try save(updated)
            } catch {
                SSTLLog.write("Could not save settings: \(error.localizedDescription)")
            }
        }
        watchRoot()
    }
}
