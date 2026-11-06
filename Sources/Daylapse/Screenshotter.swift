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
        for display in content.displays {
            do {
                guard let filter = await appRules.makeFilter(display: display, content: content, settings: settingsSnapshot) else {
                    DaylapseLog.write("Display \(display.displayID) screenshot skipped: app filter could not be applied")
                    continue
                }
                let configuration = SCStreamConfiguration()
                // SCDisplay dimensions are points; this produces half-size Retina output.
                configuration.width = Int(display.width)
                configuration.height = Int(display.height)
                configuration.showsCursor = false

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                guard await appRules.frontmostStillAllowsCapture(settings: settingsSnapshot) else {
                    DaylapseLog.write("Display \(display.displayID) screenshot discarded: app rule changed during capture")
                    continue
                }
                try await Task.detached(priority: .utility) {
                    try writeJPEG(image, displayID: display.displayID, date: date)
                }.value
            } catch {
                DaylapseLog.write("Display \(display.displayID) screenshot skipped: \(error.localizedDescription)")
            }
        }
    }

    private static func writeJPEG(_ image: CGImage, displayID: CGDirectDisplayID, date: Date) throws {
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

        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
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
