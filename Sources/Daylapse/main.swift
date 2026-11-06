import AppKit
import CoreGraphics

// The app stays in the menu bar and has no Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var didRequestScreenCaptureAccess = false
    private var captureEngine: CaptureEngine!
    private var hotkey: Hotkey!
    private var toggleItem: NSMenuItem!
    private var statusLine: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore.shared
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "○"
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "Start Screenshots", action: #selector(toggleCapture), keyEquivalent: "s")
        toggleItem.keyEquivalentModifierMask = [.option, .shift]
        menu.addItem(toggleItem)
        statusLine = NSMenuItem(title: "○", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        let blockItem = NSMenuItem(title: "Block Frontmost App", action: nil, keyEquivalent: "")
        blockItem.isEnabled = false
        menu.addItem(blockItem)
        menu.addItem(.separator())
        let exportItem = NSMenuItem(title: "Export Today as Video", action: nil, keyEquivalent: "")
        exportItem.isEnabled = false
        menu.addItem(exportItem)
        let folderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openScreenshotsFolder), keyEquivalent: "")
        menu.addItem(folderItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: "")
        settingsItem.isEnabled = false
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit Daylapse", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        captureEngine = CaptureEngine(settings: settings, capture: {
            do {
                try await Screenshotter.captureAllDisplays()
            } catch {
                DaylapseLog.write("Screenshot failed: \(error.localizedDescription)")
            }
        }, render: { [weak self] text in
            self?.statusLine.title = text
            self?.statusItem.button?.title = text
        })
        hotkey = Hotkey { [weak self] in
            Task { @MainActor in self?.toggleCapture() }
        }
        if !hotkey.register(keyCode: settings.settings.shortcut.keyCode,
                            carbonModifiers: settings.settings.shortcut.carbonModifiers) {
            DaylapseLog.write("Global shortcut registration failed")
        }
    }

    @MainActor @objc private func toggleCapture() {
        captureEngine.toggle()
        toggleItem.title = captureEngine.isStarted ? "Stop Screenshots" : "Start Screenshots"
    }

    @objc private func openScreenshotsFolder() {
        NSWorkspace.shared.open(Storage.screenshotsFolder)
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

        Task { try? await Screenshotter.captureAllDisplays() }
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
