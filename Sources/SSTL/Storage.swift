import Foundation
import CoreGraphics

enum Storage {
    // Kept in sync by SettingsStore so background code can read it.
    static let defaultRootPath = "~/Pictures/SSTL"
    nonisolated(unsafe) static var folderPath = defaultRootPath + "/Default"

    static var screenshotsFolder: URL {
        URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }

    static func dayName(for date: Date) -> String {
        formatter("yyyy-MM-dd").string(from: date)
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
                SSTLLog.write("Could not delete \(name): \(error.localizedDescription)")
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

    static func frameURL(at date: Date, displayID: CGDirectDisplayID, ext: String) throws -> URL {
        let nameFormatter = formatter("yyyy-MM-dd_HH-mm-ss")
        let dayFolder = screenshotsFolder.appendingPathComponent(dayName(for: date), isDirectory: true)
        try FileManager.default.createDirectory(at: dayFolder, withIntermediateDirectories: true)
        return dayFolder.appendingPathComponent("SSTL_\(nameFormatter.string(from: date))\(Displays.fileSuffix(for: displayID)).\(ext)")
    }
}
