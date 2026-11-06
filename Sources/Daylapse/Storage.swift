import Foundation
import CoreGraphics

enum Storage {
    // Kept in sync by SettingsStore so background code can read it.
    nonisolated(unsafe) static var folderPath = "~/Pictures/Daylapse"

    static var screenshotsFolder: URL {
        URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath, isDirectory: true)
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
        let dayFormatter = DateFormatter()
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let nameFormatter = DateFormatter()
        nameFormatter.locale = Locale(identifier: "en_US_POSIX")
        nameFormatter.timeZone = .current
        nameFormatter.dateFormat = "HHmmss"

        let dayFolder = screenshotsFolder.appendingPathComponent(dayFormatter.string(from: date), isDirectory: true)
        try FileManager.default.createDirectory(at: dayFolder, withIntermediateDirectories: true)
        return dayFolder.appendingPathComponent("\(nameFormatter.string(from: date))-d\(displayID).jpg")
    }
}
