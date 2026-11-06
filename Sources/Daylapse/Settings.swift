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

struct DaylapseSettings: Codable, Equatable {
    static let wallpaperBundleID = "com.apple.wallpaper.agent"
    static let notificationBundleID = "com.apple.notificationcenterui"

    var intervalSeconds: Int
    var captureOnStart: Bool
    var showPointer: Bool
    var pauseWhenIdleSeconds: Int
    var pauseWhenLocked: Bool
    var pauseWhenMenuOpen: Bool
    var displays: String
    var halfSizeOnRetina: Bool
    var jpegQuality: Double
    var appMode: String
    var blockedApps: [AppRuleEntry]
    var allowedApps: [AppRuleEntry]
    var showNotifications: Bool
    var showDesktopIcons: Bool
    var showWallpaper: Bool
    var backgroundHex: String
    var folderPath: String
    var deleteAfterDays: Int
    var deletePermanently: Bool
    var minFreeSpaceGB: Int
    var exportFPS: Int
    var shortcut: ShortcutSettings

    static let defaults = DaylapseSettings(
        intervalSeconds: 30,
        captureOnStart: true,
        showPointer: false,
        pauseWhenIdleSeconds: 60,
        pauseWhenLocked: true,
        pauseWhenMenuOpen: false,
        displays: "all",
        halfSizeOnRetina: true,
        jpegQuality: 0.7,
        appMode: "block",
        blockedApps: [],
        allowedApps: [],
        showNotifications: false,
        showDesktopIcons: true,
        showWallpaper: true,
        backgroundHex: "#000000",
        folderPath: "~/Pictures/Daylapse",
        deleteAfterDays: 0,
        deletePermanently: false,
        minFreeSpaceGB: 5,
        exportFPS: 12,
        shortcut: .default
    )

    private enum CodingKeys: String, CodingKey {
        case intervalSeconds, captureOnStart, showPointer, pauseWhenIdleSeconds, pauseWhenLocked, pauseWhenMenuOpen, displays
        case halfSizeOnRetina, jpegQuality, appMode, blockedApps, allowedApps
        case showNotifications, showDesktopIcons, showWallpaper, backgroundHex, hideNotifications, hideDesktopIcons
        case folderPath, deleteAfterDays
        case deletePermanently, minFreeSpaceGB, exportFPS, shortcut
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(intervalSeconds, forKey: .intervalSeconds)
        try c.encode(captureOnStart, forKey: .captureOnStart)
        try c.encode(showPointer, forKey: .showPointer)
        try c.encode(pauseWhenIdleSeconds, forKey: .pauseWhenIdleSeconds)
        try c.encode(pauseWhenLocked, forKey: .pauseWhenLocked)
        try c.encode(pauseWhenMenuOpen, forKey: .pauseWhenMenuOpen)
        try c.encode(displays, forKey: .displays)
        try c.encode(halfSizeOnRetina, forKey: .halfSizeOnRetina)
        try c.encode(jpegQuality, forKey: .jpegQuality)
        try c.encode(appMode, forKey: .appMode)
        try c.encode(blockedApps, forKey: .blockedApps)
        try c.encode(allowedApps, forKey: .allowedApps)
        try c.encode(showNotifications, forKey: .showNotifications)
        try c.encode(showDesktopIcons, forKey: .showDesktopIcons)
        try c.encode(showWallpaper, forKey: .showWallpaper)
        try c.encode(backgroundHex, forKey: .backgroundHex)
        try c.encode(folderPath, forKey: .folderPath)
        try c.encode(deleteAfterDays, forKey: .deleteAfterDays)
        try c.encode(deletePermanently, forKey: .deletePermanently)
        try c.encode(minFreeSpaceGB, forKey: .minFreeSpaceGB)
        try c.encode(exportFPS, forKey: .exportFPS)
        try c.encode(shortcut, forKey: .shortcut)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        intervalSeconds = try values.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? defaults.intervalSeconds
        captureOnStart = try values.decodeIfPresent(Bool.self, forKey: .captureOnStart) ?? defaults.captureOnStart
        showPointer = try values.decodeIfPresent(Bool.self, forKey: .showPointer) ?? defaults.showPointer
        pauseWhenIdleSeconds = try values.decodeIfPresent(Int.self, forKey: .pauseWhenIdleSeconds) ?? defaults.pauseWhenIdleSeconds
        pauseWhenLocked = try values.decodeIfPresent(Bool.self, forKey: .pauseWhenLocked) ?? defaults.pauseWhenLocked
        pauseWhenMenuOpen = try values.decodeIfPresent(Bool.self, forKey: .pauseWhenMenuOpen) ?? defaults.pauseWhenMenuOpen
        displays = try values.decodeIfPresent(String.self, forKey: .displays) ?? defaults.displays
        halfSizeOnRetina = try values.decodeIfPresent(Bool.self, forKey: .halfSizeOnRetina) ?? defaults.halfSizeOnRetina
        jpegQuality = try values.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? defaults.jpegQuality
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
        folderPath = try values.decodeIfPresent(String.self, forKey: .folderPath) ?? defaults.folderPath
        deleteAfterDays = try values.decodeIfPresent(Int.self, forKey: .deleteAfterDays) ?? defaults.deleteAfterDays
        deletePermanently = try values.decodeIfPresent(Bool.self, forKey: .deletePermanently) ?? defaults.deletePermanently
        minFreeSpaceGB = try values.decodeIfPresent(Int.self, forKey: .minFreeSpaceGB) ?? defaults.minFreeSpaceGB
        exportFPS = try values.decodeIfPresent(Int.self, forKey: .exportFPS) ?? defaults.exportFPS
        shortcut = try values.decodeIfPresent(ShortcutSettings.self, forKey: .shortcut) ?? defaults.shortcut
    }

    init(
        intervalSeconds: Int, captureOnStart: Bool, showPointer: Bool, pauseWhenIdleSeconds: Int, pauseWhenLocked: Bool,
        pauseWhenMenuOpen: Bool, displays: String, halfSizeOnRetina: Bool, jpegQuality: Double, appMode: String,
        blockedApps: [AppRuleEntry], allowedApps: [AppRuleEntry], showNotifications: Bool,
        showDesktopIcons: Bool, showWallpaper: Bool, backgroundHex: String, folderPath: String, deleteAfterDays: Int, deletePermanently: Bool,
        minFreeSpaceGB: Int, exportFPS: Int, shortcut: ShortcutSettings
    ) {
        self.intervalSeconds = intervalSeconds
        self.captureOnStart = captureOnStart
        self.showPointer = showPointer
        self.pauseWhenIdleSeconds = pauseWhenIdleSeconds
        self.pauseWhenLocked = pauseWhenLocked
        self.pauseWhenMenuOpen = pauseWhenMenuOpen
        self.displays = displays
        self.halfSizeOnRetina = halfSizeOnRetina
        self.jpegQuality = jpegQuality
        self.appMode = appMode
        self.blockedApps = blockedApps
        self.allowedApps = allowedApps
        self.showNotifications = showNotifications
        self.showDesktopIcons = showDesktopIcons
        self.showWallpaper = showWallpaper
        self.backgroundHex = backgroundHex
        self.folderPath = folderPath
        self.deleteAfterDays = deleteAfterDays
        self.deletePermanently = deletePermanently
        self.minFreeSpaceGB = minFreeSpaceGB
        self.exportFPS = exportFPS
        self.shortcut = shortcut
    }
}

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private(set) var settings: DaylapseSettings
    private let fileURL: URL

    private init() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Daylapse", isDirectory: true)
        fileURL = support.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode(DaylapseSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .defaults
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let backupURL = fileURL.appendingPathExtension("bak")
                do {
                    if !FileManager.default.fileExists(atPath: backupURL.path) {
                        try FileManager.default.moveItem(at: fileURL, to: backupURL)
                    }
                    DaylapseLog.write("Settings could not be decoded; using defaults")
                } catch {
                    DaylapseLog.write("Could not back up invalid settings: \(error.localizedDescription)")
                }
            }
        }
        Storage.folderPath = settings.folderPath
    }

    func save(_ newSettings: DaylapseSettings) throws {
        Storage.folderPath = newSettings.folderPath
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(newSettings)
        try data.write(to: fileURL, options: .atomic)
        settings = newSettings
    }
}
