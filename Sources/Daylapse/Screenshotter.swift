import CoreGraphics
import ImageIO
import ScreenCaptureKit

enum Screenshotter {
    static func captureAllDisplays(appRules: AppRules) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else {
            DaylapseLog.write("Screenshot skipped: no displays available")
            return
        }

        let date = Date()
        let settingsSnapshot = await MainActor.run { SettingsStore.shared.settings }
        let displays = settingsSnapshot.displays == "main"
            ? content.displays.filter { $0.displayID == CGMainDisplayID() }
            : content.displays
        for display in displays {
            do {
                guard let filter = await appRules.makeFilter(display: display, content: content, settings: settingsSnapshot) else {
                    DaylapseLog.write("Display \(display.displayID) screenshot skipped: app filter could not be applied")
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
                    DaylapseLog.write("Display \(display.displayID) screenshot discarded: app rule changed during capture")
                    continue
                }
                try await Task.detached(priority: .utility) {
                    try writeJPEG(image, displayID: display.displayID, date: date, quality: settingsSnapshot.jpegQuality)
                }.value
            } catch {
                DaylapseLog.write("Display \(display.displayID) screenshot skipped: \(error.localizedDescription)")
            }
        }
    }

    private static func backgroundColor(_ hex: String) -> CGColor {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return CGColor(gray: 0, alpha: 1) }
        return CGColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private static func writeJPEG(_ image: CGImage, displayID: CGDirectDisplayID, date: Date, quality: Double) throws {
        let destinationURL = try Storage.frameURL(at: date, displayID: displayID)
        let temporaryURL = destinationURL.appendingPathExtension("tmp")
        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            throw ScreenshotError.cannotCreateImageDestination
        }

        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotError.cannotWriteImage
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        DaylapseLog.write("Saved frame \(destinationURL.path)")
    }
}

private enum ScreenshotError: LocalizedError {
    case cannotCreateImageDestination
    case cannotWriteImage

    var errorDescription: String? {
        switch self {
        case .cannotCreateImageDestination: "Could not create JPEG output."
        case .cannotWriteImage: "Could not finish writing JPEG output."
        }
    }
}
