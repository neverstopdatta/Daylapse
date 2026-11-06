import AppKit
import CoreGraphics

// The app stays in the menu bar and has no Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var didRequestScreenCaptureAccess = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "○"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Take Screenshot Now", action: #selector(takeScreenshot), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Daylapse", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func takeScreenshot() {
        guard CGPreflightScreenCaptureAccess() else {
            if !didRequestScreenCaptureAccess {
                didRequestScreenCaptureAccess = true
                _ = CGRequestScreenCaptureAccess()
            }
            let alert = NSAlert()
            alert.messageText = "Screen Recording permission required"
            alert.informativeText = "Grant Daylapse access in Privacy & Security → Screen Recording, then quit and relaunch Daylapse before taking a screenshot."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        Task {
            do {
                try await Screenshotter.captureAllDisplays()
            } catch {
                DaylapseLog.write("Screenshot failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
