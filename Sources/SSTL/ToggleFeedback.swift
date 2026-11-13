import AppKit
import UserNotifications

// Sound and notification shown when capture is started or stopped with the global shortcut.
@MainActor
enum ToggleFeedback {
    // The sounds macOS ships in /System/Library/Sounds (Basso, Glass, Ping…).
    static let soundNames: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
    }()

    private static var playing: NSSound?
    private static let presenter = ForegroundPresenter()

    static func play(_ name: String) {
        playing?.stop()
        playing = NSSound(contentsOfFile: "/System/Library/Sounds/\(name).aiff", byReference: true)
        playing?.play()
    }

    static func announce(started: Bool, settings: SSTLSettings) {
        if settings.soundOnToggle { play(started ? settings.startSound : settings.stopSound) }
        if settings.notifyOnToggle { notify(started ? "Capture started" : "Capture stopped") }
    }

    // Asks macOS for permission the first time; `done` gets whether notifications are allowed.
    static func requestNotifications(_ done: @escaping @MainActor (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        center.requestAuthorization(options: [.alert]) { granted, _ in
            Task { @MainActor in done(granted) }
        }
    }

    private static func notify(_ title: String) {
        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        center.getNotificationSettings { current in
            guard current.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    // Without this, macOS hides notifications while the app is frontmost (for example with Settings open).
    private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
            completionHandler([.banner])
        }
    }
}
