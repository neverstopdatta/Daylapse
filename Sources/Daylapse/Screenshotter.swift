import CoreGraphics
import ImageIO
import ScreenCaptureKit

enum Screenshotter {
    static func captureAllDisplays() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !content.displays.isEmpty else {
            DaylapseLog.write("Screenshot skipped: no displays available")
            return
        }

        let date = Date()
        for display in content.displays {
            do {
                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let configuration = SCStreamConfiguration()
                // SCDisplay dimensions are points; this produces half-size Retina output.
                configuration.width = Int(display.width)
                configuration.height = Int(display.height)
                configuration.showsCursor = false

                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                try writeJPEG(image, displayID: display.displayID, date: date)
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
