import Foundation
import ImageIO

enum ExportError: LocalizedError {
    case ffmpegMissing
    case noFrames(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing: "ffmpeg was not found. Install it (for example with Homebrew: brew install ffmpeg) or choose its location in Settings > Timelapse."
        case .noFrames(let day): "No frames found for \(day)."
        case .failed(let detail): "ffmpeg failed: \(detail)"
        }
    }
}

enum Exporter {
    struct Day: Identifiable {
        let name: String
        let frameCount: Int
        // Frames in the busiest display, which sets the length of the video.
        let videoFrames: Int
        var id: String { name }
    }

    // Kept in sync by SettingsStore so background code can read it.
    nonisolated(unsafe) static var customFFmpegPath = ""

    // Order: the path chosen in Settings, common install folders (Homebrew, MacPorts), the app's PATH,
    // then the user's login-shell PATH, which covers Nix and other custom setups.
    static var ffmpegURL: URL? { ffmpegLocation()?.url }

    // `custom` is true when the path chosen in Settings is the one in use.
    static func ffmpegLocation() -> (url: URL, custom: Bool)? {
        let fm = FileManager.default
        var candidates: [String] = []
        if !customFFmpegPath.isEmpty { candidates.append(customFFmpegPath) }
        let folders = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        candidates += folders.map { $0 + "/ffmpeg" }
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return (URL(fileURLWithPath: found), found == customFFmpegPath)
        }
        if let found = loginShellFFmpeg(), fm.isExecutableFile(atPath: found) { return (URL(fileURLWithPath: found), false) }
        return nil
    }

    // The version number if the file really is ffmpeg, otherwise nil.
    static func ffmpegVersion(at path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let words = String(decoding: data, as: UTF8.self).split(separator: "\n").first?.split(separator: " ") ?? []
        guard process.terminationStatus == 0, words.count >= 3, words[0] == "ffmpeg", words[1] == "version" else { return nil }
        return String(words[2])
    }

    private static func loginShellFFmpeg() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "command -v ffmpeg"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && path.hasPrefix("/") ? path : nil
    }

    static func isDayName(_ name: String) -> Bool {
        name.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    static func days(in folder: URL) -> [Day] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter(isDayName).sorted(by: >).map { name in
            let all = frames(day: name, in: folder)
            let longest = Dictionary(grouping: all) { displayKey($0) }.values.map(\.count).max() ?? 0
            return Day(name: name, frameCount: all.count, videoFrames: longest)
        }
    }

    // New names end in "_d<id>" for non-main displays, old ones in "-d<id>"; no suffix means the main display.
    private static func displayKey(_ frame: URL) -> String {
        let name = frame.deletingPathExtension().lastPathComponent
        return name.range(of: #"[-_]d(\d+)$"#, options: .regularExpression).map { String(name[$0].dropFirst(2)) } ?? "0"
    }

    private static func frames(day: String, in folder: URL) -> [URL] {
        let dir = folder.appendingPathComponent(day, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // Blocking: call from a background queue. Returns the videos written.
    static func export(day: String, fps: Int, in folder: URL) throws -> [URL] {
        try export(days: [day], fps: fps, in: folder)
    }

    // One video per display covering every given day, in capture-time order.
    static func export(days: [String], fps: Int, in folder: URL) throws -> [URL] {
        guard let ffmpeg = ffmpegURL else { throw ExportError.ffmpegMissing }
        let ordered = days.sorted()
        let label = ordered.count > 1 ? "SSTL_\(ordered[0])_to_\(ordered[ordered.count - 1])" : ordered[0]
        let all = ordered.flatMap { frames(day: $0, in: folder) }
            .sorted { (Storage.timestamp(of: $0) ?? .distantPast, $0.lastPathComponent) < (Storage.timestamp(of: $1) ?? .distantPast, $1.lastPathComponent) }
        guard !all.isEmpty else { throw ExportError.noFrames(label) }

        var groups: [String: [URL]] = [:]
        for frame in all {
            groups[displayKey(frame), default: []].append(frame)
        }
        let exports = folder.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)

        var outputs: [URL] = []
        for (display, files) in groups.sorted(by: { $0.key < $1.key }) {
            let out = exports.appendingPathComponent(groups.count > 1 ? "\(label)-d\(display).mp4" : "\(label).mp4")
            try encode(files, fps: fps, ffmpeg: ffmpeg, out: out)
            outputs.append(out)
        }
        return outputs
    }

    private static func encode(_ files: [URL], fps: Int, ffmpeg: URL, out: URL) throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("daylapse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        for (index, file) in files.enumerated() {
            let link = tmp.appendingPathComponent(String(format: "%06d.jpg", index + 1))
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        }
        var width = 0, height = 0
        if let last = files.last, let src = CGImageSourceCreateWithURL(last as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        }
        width -= width % 2
        height -= height % 2
        guard width > 0, height > 0 else { throw ExportError.failed("could not read frame size") }

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-y", "-framerate", String(fps), "-i", tmp.appendingPathComponent("%06d.jpg").path,
            "-vf", "scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2,scale=out_range=tv,format=yuv420p",
            "-c:v", "h264_videotoolbox", "-q:v", "65", "-an", "-movflags", "+faststart", out.path,
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(decoding: errData.suffix(400), as: UTF8.self)
            throw ExportError.failed(text)
        }
    }
}
