import Foundation

struct AppRuleEntry: Codable, Hashable {
    var bundleID: String
    var name: String
}

struct ShortcutSettings: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = ShortcutSettings(keyCode: 1, carbonModifiers: 2560)
}

struct DaylapseSettings: Codable {
    var intervalSeconds: Int
    var showPointer: Bool
    var pauseWhenIdleSeconds: Int
    var pauseWhenLocked: Bool
    var displays: String
    var halfSizeOnRetina: Bool
    var jpegQuality: Double
    var appMode: String
    var blockedApps: [AppRuleEntry]
    var allowedApps: [AppRuleEntry]
    var hideNotifications: Bool
    var hideDesktopIcons: Bool
    var folderPath: String
    var deleteAfterDays: Int
    var deletePermanently: Bool
    var minFreeSpaceGB: Int
    var exportFPS: Int
    var shortcut: ShortcutSettings

    static let defaults = DaylapseSettings(
        intervalSeconds: 30,
        showPointer: false,
        pauseWhenIdleSeconds: 60,
        pauseWhenLocked: true,
        displays: "all",
        halfSizeOnRetina: true,
        jpegQuality: 0.7,
        appMode: "block",
        blockedApps: [],
        allowedApps: [],
        hideNotifications: true,
        hideDesktopIcons: false,
        folderPath: "~/Pictures/Daylapse",
        deleteAfterDays: 0,
        deletePermanently: false,
        minFreeSpaceGB: 5,
        exportFPS: 12,
        shortcut: .default
    )

    private enum CodingKeys: String, CodingKey {
        case intervalSeconds, showPointer, pauseWhenIdleSeconds, pauseWhenLocked, displays
        case halfSizeOnRetina, jpegQuality, appMode, blockedApps, allowedApps
        case hideNotifications, hideDesktopIcons, folderPath, deleteAfterDays
        case deletePermanently, minFreeSpaceGB, exportFPS, shortcut
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        intervalSeconds = try values.decodeIfPresent(Int.self, forKey: .intervalSeconds) ?? defaults.intervalSeconds
        showPointer = try values.decodeIfPresent(Bool.self, forKey: .showPointer) ?? defaults.showPointer
        pauseWhenIdleSeconds = try values.decodeIfPresent(Int.self, forKey: .pauseWhenIdleSeconds) ?? defaults.pauseWhenIdleSeconds
        pauseWhenLocked = try values.decodeIfPresent(Bool.self, forKey: .pauseWhenLocked) ?? defaults.pauseWhenLocked
        displays = try values.decodeIfPresent(String.self, forKey: .displays) ?? defaults.displays
        halfSizeOnRetina = try values.decodeIfPresent(Bool.self, forKey: .halfSizeOnRetina) ?? defaults.halfSizeOnRetina
        jpegQuality = try values.decodeIfPresent(Double.self, forKey: .jpegQuality) ?? defaults.jpegQuality
        appMode = try values.decodeIfPresent(String.self, forKey: .appMode) ?? defaults.appMode
        blockedApps = try values.decodeIfPresent([AppRuleEntry].self, forKey: .blockedApps) ?? defaults.blockedApps
        allowedApps = try values.decodeIfPresent([AppRuleEntry].self, forKey: .allowedApps) ?? defaults.allowedApps
        hideNotifications = try values.decodeIfPresent(Bool.self, forKey: .hideNotifications) ?? defaults.hideNotifications
        hideDesktopIcons = try values.decodeIfPresent(Bool.self, forKey: .hideDesktopIcons) ?? defaults.hideDesktopIcons
        folderPath = try values.decodeIfPresent(String.self, forKey: .folderPath) ?? defaults.folderPath
        deleteAfterDays = try values.decodeIfPresent(Int.self, forKey: .deleteAfterDays) ?? defaults.deleteAfterDays
        deletePermanently = try values.decodeIfPresent(Bool.self, forKey: .deletePermanently) ?? defaults.deletePermanently
        minFreeSpaceGB = try values.decodeIfPresent(Int.self, forKey: .minFreeSpaceGB) ?? defaults.minFreeSpaceGB
        exportFPS = try values.decodeIfPresent(Int.self, forKey: .exportFPS) ?? defaults.exportFPS
        shortcut = try values.decodeIfPresent(ShortcutSettings.self, forKey: .shortcut) ?? defaults.shortcut
    }

    init(
        intervalSeconds: Int, showPointer: Bool, pauseWhenIdleSeconds: Int, pauseWhenLocked: Bool,
        displays: String, halfSizeOnRetina: Bool, jpegQuality: Double, appMode: String,
        blockedApps: [AppRuleEntry], allowedApps: [AppRuleEntry], hideNotifications: Bool,
        hideDesktopIcons: Bool, folderPath: String, deleteAfterDays: Int, deletePermanently: Bool,
        minFreeSpaceGB: Int, exportFPS: Int, shortcut: ShortcutSettings
    ) {
        self.intervalSeconds = intervalSeconds
        self.showPointer = showPointer
        self.pauseWhenIdleSeconds = pauseWhenIdleSeconds
        self.pauseWhenLocked = pauseWhenLocked
        self.displays = displays
        self.halfSizeOnRetina = halfSizeOnRetina
        self.jpegQuality = jpegQuality
        self.appMode = appMode
        self.blockedApps = blockedApps
        self.allowedApps = allowedApps
        self.hideNotifications = hideNotifications
        self.hideDesktopIcons = hideDesktopIcons
        self.folderPath = folderPath
        self.deleteAfterDays = deleteAfterDays
        self.deletePermanently = deletePermanently
        self.minFreeSpaceGB = minFreeSpaceGB
        self.exportFPS = exportFPS
        self.shortcut = shortcut
    }
}

@MainActor
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
    }

    func save(_ newSettings: DaylapseSettings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(newSettings)
        try data.write(to: fileURL, options: .atomic)
        settings = newSettings
    }
}
