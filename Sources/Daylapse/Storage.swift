import Foundation
import CoreGraphics

enum Storage {
    // Kept in sync by SettingsStore so background code can read it.
    static let defaultFolderPath = "~/Pictures/Screenshots Timelapse"
    nonisolated(unsafe) static var folderPath = defaultFolderPath

    // Moves data from the old "Daylapse" locations once, if the new ones do not exist yet.
    static func migrateLegacyPaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for (old, new) in [
            ("Pictures/Daylapse", "Pictures/Screenshots Timelapse"),
            ("Library/Application Support/Daylapse", "Library/Application Support/Screenshots Timelapse"),
            ("Library/Logs/Daylapse.log", "Library/Logs/Screenshots Timelapse.log"),
        ] {
            let oldURL = home.appendingPathComponent(old), newURL = home.appendingPathComponent(new)
            if FileManager.default.fileExists(atPath: oldURL.path), !FileManager.default.fileExists(atPath: newURL.path) {
                try? FileManager.default.moveItem(at: oldURL, to: newURL)
            }
        }
    }

    static var screenshotsFolder: URL {
        URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    // Screenshots taken before this hour belong to the previous day's folder.
    nonisolated(unsafe) static var dayStartHour = 0

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    static func dayName(for date: Date) -> String {
        formatter("yyyy-MM-dd").string(from: date.addingTimeInterval(-TimeInterval(dayStartHour * 3600)))
    }

    // The real capture time, read from the file name (old names fall back to the folder date).
    static func timestamp(of frame: URL) -> Date? {
        let name = frame.deletingPathExtension().lastPathComponent
        if let range = name.range(of: #"\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}"#, options: .regularExpression) {
            return formatter("yyyy-MM-dd_HH-mm-ss").date(from: String(name[range]))
        }
        let day = frame.deletingLastPathComponent().lastPathComponent
        return formatter("yyyy-MM-dd HHmmss").date(from: day + " " + name.prefix(6))
    }

    // Screenshots filed under a different day than the current day-start setting expects.
    static func misfiled(in folder: URL) -> [(url: URL, day: String)] {
        var result: [(URL, String)] = []
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where dayDate(name) != nil {
            let dir = folder.appendingPathComponent(name, isDirectory: true)
            for file in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            where file.pathExtension == "jpg" {
                guard let time = timestamp(of: file) else { continue }
                let expected = dayName(for: time)
                if expected != name { result.append((file, expected)) }
            }
        }
        return result
    }

    @discardableResult
    static func refile(_ items: [(url: URL, day: String)], in folder: URL) -> Int {
        var moved = 0
        for item in items {
            let dir = folder.appendingPathComponent(item.day, isDirectory: true)
            let destination = dir.appendingPathComponent(item.url.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: item.url, to: destination)
                moved += 1
            } catch {
                DaylapseLog.write("Could not move \(item.url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return moved
    }

    static func dayDate(_ name: String) -> Date? {
        guard Exporter.isDayName(name) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: name)
    }

    // Only folders named exactly YYYY-MM-DD are touched. Nil `days` means every day folder.
    @discardableResult
    static func deleteDays(in folder: URL, olderThan days: Int?, permanently: Bool) -> Int {
        let cutoff = days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: Date())) }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var removed = 0
        for name in names {
            guard let date = dayDate(name) else { continue }
            if let cutoff, date >= cutoff { continue }
            let url = folder.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            do {
                if permanently {
                    try FileManager.default.removeItem(at: url)
                } else {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
                removed += 1
            } catch {
                DaylapseLog.write("Could not delete \(name): \(error.localizedDescription)")
            }
        }
        return removed
    }

    static func usedBytes(in folder: URL) -> Int64 {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var total: Int64 = 0
        for name in names where dayDate(name) != nil {
            let dir = folder.appendingPathComponent(name)
            for file in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? [] {
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return total
    }

    static func frameURL(at date: Date, displayID: CGDirectDisplayID) throws -> URL {
        let nameFormatter = formatter("yyyy-MM-dd_HH-mm-ss")
        let dayFolder = screenshotsFolder.appendingPathComponent(dayName(for: date), isDirectory: true)
        try FileManager.default.createDirectory(at: dayFolder, withIntermediateDirectories: true)
        // The main display keeps the plain name; other displays get a suffix so names never collide.
        let suffix = displayID == CGMainDisplayID() ? "" : "_d\(displayID)"
        return dayFolder.appendingPathComponent("SSTL_\(nameFormatter.string(from: date))\(suffix).jpg")
    }
}
