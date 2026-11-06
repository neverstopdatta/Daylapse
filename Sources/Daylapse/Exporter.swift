import Foundation
import ImageIO

enum ExportError: LocalizedError {
    case ffmpegMissing
    case noFrames(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing: "ffmpeg was not found. Install it with: brew install ffmpeg"
        case .noFrames(let day): "No frames found for \(day)."
        case .failed(let detail): "ffmpeg failed: \(detail)"
        }
    }
}

enum Exporter {
    struct Day: Identifiable {
        let name: String
        let frameCount: Int
        var id: String { name }
    }

    static var ffmpegURL: URL? {
        ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func isDayName(_ name: String) -> Bool {
        name.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    static func days(in folder: URL) -> [Day] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter(isDayName).sorted(by: >).map { name in
            Day(name: name, frameCount: frames(day: name, in: folder).count)
        }
    }

    private static func frames(day: String, in folder: URL) -> [URL] {
        let dir = folder.appendingPathComponent(day, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // Blocking: call from a background queue. Returns the videos written.
    static func export(day: String, fps: Int, in folder: URL) throws -> [URL] {
        guard let ffmpeg = ffmpegURL else { throw ExportError.ffmpegMissing }
        let all = frames(day: day, in: folder)
        guard !all.isEmpty else { throw ExportError.noFrames(day) }

        var groups: [String: [URL]] = [:]
        for frame in all {
            let name = frame.deletingPathExtension().lastPathComponent
            let display = name.components(separatedBy: "-d").last ?? "0"
            groups[display, default: []].append(frame)
        }
        let exports = folder.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)

        var outputs: [URL] = []
        for (display, files) in groups.sorted(by: { $0.key < $1.key }) {
            let out = exports.appendingPathComponent(groups.count > 1 ? "\(day)-d\(display).mp4" : "\(day).mp4")
            try encode(files.sorted { $0.lastPathComponent < $1.lastPathComponent }, fps: fps, ffmpeg: ffmpeg, out: out)
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
