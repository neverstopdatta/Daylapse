import Foundation

enum SSTLLog {
    private static let lock = NSLock()
    private static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Screenshots Timelapse.log")

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        do {
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } else {
                try Data(line.utf8).write(to: logURL, options: .atomic)
            }
        } catch {
            NSLog("SSTL log write failed: %@", error.localizedDescription)
        }
    }
}
