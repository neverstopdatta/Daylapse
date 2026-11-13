import AVFoundation
import Foundation
import ImageIO

enum ExportError: LocalizedError {
    case noFrames(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noFrames(let day): "No frames found for \(day)."
        case .cancelled: "Export cancelled."
        case .failed(let detail): "Export failed: \(detail)"
        }
    }
}

// Lets the Timelapse tab stop an export that runs on a background queue.
final class ExportJob: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var isCancelled: Bool { lock.withLock { stopped } }
    func cancel() { lock.withLock { stopped = true } }
}

// Writes videos with AVFoundation: each frame is decoded, fitted into one size and handed to the hardware encoder.
enum Exporter {
    struct Day: Identifiable {
        let name: String
        let frameCount: Int
        // Frames in the busiest display, which sets the length of the video.
        let videoFrames: Int
        var id: String { name }
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

    // Names end in "_d<key>" for every display but the built-in one (no suffix). Older files used a numeric
    // display ID, with "_" or "-" before the "d".
    private static func displayKey(_ frame: URL) -> String {
        let name = frame.deletingPathExtension().lastPathComponent
        return name.range(of: #"[-_]d([0-9a-f]+)$"#, options: .regularExpression).map { String(name[$0].dropFirst(2)) } ?? "0"
    }

    private static let frameExtensions: Set<String> = ["jpg", "png", "heic"]

    private static func frames(day: String, in folder: URL) -> [URL] {
        let dir = folder.appendingPathComponent(day, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { frameExtensions.contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // Blocking: call from a background queue. Each batch (one or more days) becomes one video per display.
    // `progress` gets 0...1 across everything; the call throws `.cancelled` once the job is cancelled.
    static func export(batches: [[String]], fps: Int, format: String = "mp4", in folder: URL, job: ExportJob, progress: (Double) -> Void) throws -> [URL] {
        let ext = format == "gif" ? "gif" : "mp4"
        struct Task { let out: URL; let files: [URL] }
        let exports = folder.appendingPathComponent("Exports", isDirectory: true)
        var tasks: [Task] = []
        for days in batches {
            let ordered = days.sorted()
            let label = ordered.count > 1 ? "SSTL_\(ordered[0])_to_\(ordered[ordered.count - 1])" : ordered[0]
            let all = ordered.flatMap { frames(day: $0, in: folder) }
                .sorted { (Storage.timestamp(of: $0) ?? .distantPast, $0.lastPathComponent) < (Storage.timestamp(of: $1) ?? .distantPast, $1.lastPathComponent) }
            guard !all.isEmpty else { throw ExportError.noFrames(label) }
            let groups = Dictionary(grouping: all, by: displayKey)
            for (display, files) in groups.sorted(by: { $0.key < $1.key }) {
                tasks.append(Task(out: exports.appendingPathComponent(groups.count > 1 ? "\(label)-d\(display).\(ext)" : "\(label).\(ext)"), files: files))
            }
        }
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)

        let total = max(1, tasks.reduce(0) { $0 + (ext == "gif" ? min($1.files.count, gifMaxFrames) : $1.files.count) })
        var finished = 0
        var outputs: [URL] = []
        for task in tasks {
            let before = finished
            let report = { (done: Int) in progress(Double(before + done) / Double(total)) }
            if ext == "gif" {
                try encodeGIF(task.files, fps: fps, out: task.out, job: job, report: report)
            } else {
                try encode(task.files, fps: fps, out: task.out, job: job, report: report)
            }
            finished += ext == "gif" ? min(task.files.count, gifMaxFrames) : task.files.count
            outputs.append(task.out)
        }
        return outputs
    }

    // Read from the file header only, so it stays quick across thousands of frames.
    private static func pixelSize(_ file: URL) -> (width: Int, height: Int) {
        guard let src = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return (0, 0) }
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    private static func encode(_ files: [URL], fps: Int, out: URL, job: ExportJob, report: (Int) -> Void) throws {
        // The newest frame sets the video size; frames of other sizes are scaled to fit and centred on black.
        guard let last = files.last.map(pixelSize), last.width > 1, last.height > 1 else { throw ExportError.failed("could not read frame size") }
        let width = last.width - last.width % 2, height = last.height - last.height % 2

        try? FileManager.default.removeItem(at: out)
        let writer = try AVAssetWriter(outputURL: out, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        // H.264 hardware encoders stop at about 4096 px; wider frames use HEVC.
        let large = max(width, height) > 4096
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: large ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: 0.7,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
            ],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ])
        guard writer.canAdd(input) else { throw ExportError.failed("the video format is not supported") }
        writer.add(input)
        guard writer.startWriting() else { throw ExportError.failed(writer.error?.localizedDescription ?? "could not start writing") }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw ExportError.failed("no pixel buffer pool") }

        func abort(_ error: ExportError) -> ExportError {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: out)
            removeScratch(beside: out)
            return error
        }

        // Frames are decoded several at a time while the previous batch is being appended, so decoding
        // and encoding overlap. The batch size keeps the buffers in flight to a few hundred MB.
        let batch = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 256_000_000 / (width * height * 4)))
        func renderBatch(from start: Int) -> [CVPixelBuffer?] {
            let count = min(batch, files.count - start)
            var buffers = [CVPixelBuffer?](repeating: nil, count: count)
            buffers.withUnsafeMutableBufferPointer { slots in
                let base = slots.baseAddress!
                DispatchQueue.concurrentPerform(iterations: count) { i in
                    var buffer: CVPixelBuffer?
                    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                    if let buffer {
                        render(files[start + i], into: buffer, width: width, height: height)
                        base[i] = buffer
                    }
                }
            }
            return buffers
        }

        var index = 0
        var current = renderBatch(from: 0)
        while index < files.count {
            if job.isCancelled { throw abort(.cancelled) }
            let nextStart = index + current.count
            var next: [CVPixelBuffer?] = []
            let rendering = DispatchGroup()
            if nextStart < files.count {
                DispatchQueue.global(qos: .userInitiated).async(group: rendering) { next = renderBatch(from: nextStart) }
            }
            for (i, buffer) in current.enumerated() {
                guard let buffer else { rendering.wait(); throw abort(.failed("out of memory")) }
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed || job.isCancelled { break }
                    usleep(1_000)
                }
                if job.isCancelled { rendering.wait(); throw abort(.cancelled) }
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index + i), timescale: CMTimeScale(fps))) else {
                    rendering.wait()
                    throw abort(.failed(writer.error?.localizedDescription ?? "the encoder stopped"))
                }
            }
            rendering.wait()
            index = nextStart
            current = next
            report(index)
        }
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw abort(.failed(writer.error?.localizedDescription ?? "could not finish the video")) }
        removeScratch(beside: out)
    }

    // Writing for network use leaves a scratch copy named "<video>.mp4.sb-…" beside the video.
    private static func removeScratch(beside out: URL) {
        let folder = out.deletingLastPathComponent()
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(out.lastPathComponent + ".sb-") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    // Draws one frame into the buffer, scaled to fit and centred on black.
    private static func render(_ file: URL, into buffer: CVPixelBuffer, width: Int, height: Int) {
        for (key, value) in [(kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2),
                             (kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2),
                             (kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2)] {
            CVBufferSetAttachment(buffer, key, value, .shouldPropagate)
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        draw(file, in: context, width: width, height: height, maxPixels: nil)
    }

    // Decodes a frame and draws it scaled to fit and centred on black. `maxPixels` lets the decoder shrink big frames early.
    private static func draw(_ file: URL, in context: CGContext, width: Int, height: Int, maxPixels: Int?) {
        let options: CFDictionary? = maxPixels.map {
            [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
             kCGImageSourceThumbnailMaxPixelSize: $0] as CFDictionary
        }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = (options == nil ? CGImageSourceCreateImageAtIndex(source, 0, nil)
                                          : CGImageSourceCreateThumbnailAtIndex(source, 0, options)) else {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            return
        }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let rect: CGRect
        if w - CGFloat(width) >= 0, w - CGFloat(width) <= 1, h - CGFloat(height) >= 0, h - CGFloat(height) <= 1 {
            // An odd pixel was trimmed from the video size: crop it instead of resampling the whole frame.
            rect = CGRect(x: 0, y: CGFloat(height) - h, width: w, height: h)
        } else {
            let scale = min(CGFloat(width) / w, CGFloat(height) / h)
            rect = CGRect(x: (CGFloat(width) - w * scale) / 2, y: (CGFloat(height) - h * scale) / 2, width: w * scale, height: h * scale)
        }
        // Black bars only when the frame does not cover the whole video.
        if rect.width < CGFloat(width) || rect.height < CGFloat(height) {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.interpolationQuality = .high
        context.draw(image, in: rect)
    }

    // GIFs are for short clips. ImageIO keeps every frame in memory until the file is finished (about 3 MB each
    // at this size), so frames are shrunk and long selections are thinned to evenly spaced frames.
    static let gifMaxFrames = 300
    private static let gifMaxSide = 720.0

    private static func encodeGIF(_ all: [URL], fps: Int, out: URL, job: ExportJob, report: (Int) -> Void) throws {
        let files = all.count <= gifMaxFrames ? all : (0..<gifMaxFrames).map { all[$0 * all.count / gifMaxFrames] }
        guard let last = files.last.map(pixelSize), last.width > 1, last.height > 1 else { throw ExportError.failed("could not read frame size") }
        let scale = min(1, gifMaxSide / Double(max(last.width, last.height)))
        let width = max(2, Int((Double(last.width) * scale).rounded())), height = max(2, Int((Double(last.height) * scale).rounded()))

        try? FileManager.default.removeItem(at: out)
        guard let destination = CGImageDestinationCreateWithURL(out as CFURL, "com.compuserve.gif" as CFString, files.count, nil) else {
            throw ExportError.failed("could not create the GIF")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: max(0.02, 1 / Double(fps))]] as CFDictionary
        for (index, file) in files.enumerated() {
            if job.isCancelled {
                try? FileManager.default.removeItem(at: out)
                throw ExportError.cancelled
            }
            try autoreleasepool {
                guard let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ) else { throw ExportError.failed("out of memory") }
                draw(file, in: context, width: width, height: height, maxPixels: max(width, height))
                guard let image = context.makeImage() else { throw ExportError.failed("out of memory") }
                CGImageDestinationAddImage(destination, image, frameProperties)
            }
            report(index + 1)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: out)
            throw ExportError.failed("could not write the GIF")
        }
    }
}
