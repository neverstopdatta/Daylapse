import Foundation
import CoreGraphics

enum Storage {
    static let screenshotsFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/Daylapse", isDirectory: true)

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
