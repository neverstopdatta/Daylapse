import CoreGraphics
import ImageIO
import ScreenCaptureKit

enum Screenshotter {
    static func captureAllDisplays(appRules: AppRules) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else {
            SSTLLog.write("Screenshot skipped: no displays available")
            return
        }

        let date = Date()
        let settingsSnapshot = await MainActor.run { SettingsStore.shared.settings }
        let displays = content.displays.filter { Displays.matches(settingsSnapshot.displays, id: $0.displayID) }
        for display in displays {
            do {
                guard let filter = await appRules.makeFilter(display: display, content: content, settings: settingsSnapshot) else {
                    SSTLLog.write("Display \(display.displayID) screenshot skipped: app filter could not be applied")
                    continue
                }
                let configuration = SCStreamConfiguration()
                // SCDisplay dimensions are points; scale 1 gives half-size Retina output.
                let scale = settingsSnapshot.halfSizeOnRetina ? 1 : CGFloat(filter.pointPixelScale)
                configuration.width = Int(CGFloat(display.width) * scale)
                configuration.height = Int(CGFloat(display.height) * scale)
                configuration.showsCursor = settingsSnapshot.showPointer
                // SCStreamConfiguration does not retain this colour, so keep it alive until the capture ends.
                let background = backgroundColor(settingsSnapshot.backgroundHex)
                configuration.backgroundColor = background

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                withExtendedLifetime(background) {}
                guard await appRules.frontmostStillAllowsCapture(settings: settingsSnapshot) else {
                    SSTLLog.write("Display \(display.displayID) screenshot discarded: app rule changed during capture")
                    continue
                }
                try await Task.detached(priority: .utility) {
                    try writeImage(image, displayID: display.displayID, date: date, format: settingsSnapshot.imageFormat, quality: settingsSnapshot.jpegQuality)
                }.value
            } catch {
                SSTLLog.write("Display \(display.displayID) screenshot skipped: \(error.localizedDescription)")
            }
        }
    }

    private static func backgroundColor(_ hex: String) -> CGColor {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return CGColor(gray: 0, alpha: 1) }
        return CGColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    // (file extension, type identifier) per format; HEIC is used only where ImageIO can write it.
    static func imageType(_ format: String) -> (ext: String, uti: String) {
        switch format {
        case "png": ("png", "public.png")
        case "heic" where heicAvailable: ("heic", "public.heic")
        default: ("jpg", "public.jpeg")
        }
    }

    static var heicAvailable: Bool {
        (CGImageDestinationCopyTypeIdentifiers() as? [String])?.contains("public.heic") ?? false
    }

    private static func writeImage(_ image: CGImage, displayID: CGDirectDisplayID, date: Date, format: String, quality: Double) throws {
        let type = imageType(format)
        let destinationURL = try Storage.frameURL(at: date, displayID: displayID, ext: type.ext)
        let temporaryURL = destinationURL.appendingPathExtension("tmp")
        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            type.uti as CFString,
            1,
            nil
        ) else {
            throw ScreenshotError.cannotCreateImageDestination
        }

        // PNG is lossless and takes no quality setting.
        let options: [CFString: Any] = type.ext == "png" ? [:] : [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotError.cannotWriteImage
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        SSTLLog.write("Saved frame \(destinationURL.path)")
    }
}

private enum ScreenshotError: LocalizedError {
    case cannotCreateImageDestination
    case cannotWriteImage

    var errorDescription: String? {
        switch self {
        case .cannotCreateImageDestination: "Could not create the image file."
        case .cannotWriteImage: "Could not finish writing the image file."
        }
    }
}
