import AppKit
import CoreGraphics

// The app stays in the menu bar and has no Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var didRequestScreenCaptureAccess = false
    private var captureEngine: CaptureEngine!
    private var hotkey: Hotkey!
    private var toggleItem: NSMenuItem!
    private var statusLine: NSMenuItem!
    private var settingsWindowController: SettingsWindowController?
    private var appRules: AppRules!
    private var blockItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore.shared
        appRules = AppRules(settings: settings)
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
        blockItem = NSMenuItem(title: "Block Frontmost App", action: #selector(toggleFrontmostRule), keyEquivalent: "")
        menu.addItem(blockItem)
        menu.addItem(.separator())
        let exportItem = NSMenuItem(title: "Export Today as Video", action: nil, keyEquivalent: "")
        exportItem.isEnabled = false
        menu.addItem(exportItem)
        let folderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openScreenshotsFolder), keyEquivalent: "")
        menu.addItem(folderItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit Daylapse", action: #selector(quit), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu

        captureEngine = CaptureEngine(settings: settings, capture: {
            do {
                try await Screenshotter.captureAllDisplays(appRules: self.appRules)
            } catch {
                DaylapseLog.write("Screenshot failed: \(error.localizedDescription)")
            }
        }, pauseReason: { [weak self] in
            self?.appRules.pauseReason() ?? .notAllowed
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

    @MainActor @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showSettings()
    }

    @MainActor @objc private func toggleFrontmostRule() {
        do {
            try appRules.toggleCurrentRule()
            updateBlockMenuItem()
        } catch {
            DaylapseLog.write("Could not update app rule: \(error.localizedDescription)")
        }
    }

    @MainActor func menuWillOpen(_ menu: NSMenu) {
        updateBlockMenuItem()
    }

    @MainActor private func updateBlockMenuItem() {
        if let title = appRules.menuTitle() {
            blockItem.title = title
            blockItem.isEnabled = true
        } else {
            blockItem.title = "Block Frontmost App"
            blockItem.isEnabled = false
        }
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

        Task { try? await Screenshotter.captureAllDisplays(appRules: appRules) }
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
