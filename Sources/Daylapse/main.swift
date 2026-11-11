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
    private var settingsObservers: [NSObjectProtocol] = []
    private var appRules: AppRules!
    private var systemState: SystemState!
    private var blockItem: NSMenuItem!
    private var exportItem: NSMenuItem!

    private lazy var menuBarImage: NSImage? = Self.menuBarIcon()

    private static func menuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Storage.migrateLegacyPaths()
        let settings = SettingsStore.shared
        appRules = AppRules(settings: settings)
        systemState = SystemState(settings: settings)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = menuBarImage
        statusItem.button?.title = ""
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "Start Screenshots", action: #selector(toggleCapture), keyEquivalent: "s")
        applyToggleShortcut(settings.settings.shortcut.keyCode, settings.settings.shortcut.carbonModifiers)
        menu.addItem(toggleItem)
        statusLine = NSMenuItem(title: "○", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        blockItem = NSMenuItem(title: "Block Frontmost App", action: #selector(toggleFrontmostRule), keyEquivalent: "")
        menu.addItem(blockItem)
        menu.addItem(.separator())
        exportItem = NSMenuItem(title: "Export Today as Video", action: #selector(exportToday), keyEquivalent: "")
        menu.addItem(exportItem)
        let folderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openScreenshotsFolder), keyEquivalent: "")
        menu.addItem(folderItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu

        captureEngine = CaptureEngine(settings: settings, capture: {
            do {
                try await Screenshotter.captureAllDisplays(appRules: self.appRules)
            } catch {
                DaylapseLog.write("Screenshot failed: \(error.localizedDescription)")
            }
        }, pauseReason: { [weak self] in
            guard let self else { return .notAllowed }
            return self.systemState.pauseReason() ?? self.appRules.pauseReason()
        }, render: { [weak self] text in
            self?.renderStatus(text)
        })
        hotkey = Hotkey { [weak self] in
            Task { @MainActor in self?.toggleCapture() }
        }
        ShortcutRegistrar.apply = { [weak self] keyCode, modifiers in
            guard let self else { return false }
            if self.hotkey.register(keyCode: keyCode, carbonModifiers: modifiers) {
                self.applyToggleShortcut(keyCode, modifiers)
                return true
            }
            let old = SettingsStore.shared.settings.shortcut
            _ = self.hotkey.register(keyCode: old.keyCode, carbonModifiers: old.carbonModifiers)
            return false
        }
        runRetention()
        let retentionTimer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runRetention() }
        }
        RunLoop.main.add(retentionTimer, forMode: .common)
        if !hotkey.register(keyCode: settings.settings.shortcut.keyCode,
                            carbonModifiers: settings.settings.shortcut.carbonModifiers) {
            DaylapseLog.write("Global shortcut registration failed")
        }
    }

    @MainActor private func applyToggleShortcut(_ keyCode: UInt32, _ modifiers: UInt32) {
        toggleItem.keyEquivalent = KeyNames.character(for: keyCode) ?? ""
        toggleItem.keyEquivalentModifierMask = KeyNames.menuModifierMask(modifiers)
    }

    @MainActor private func runRetention() {
        let current = SettingsStore.shared.settings
        guard current.deleteAfterDays > 0 else { return }
        let folder = Storage.screenshotsFolder
        DispatchQueue.global(qos: .utility).async {
            let count = Storage.deleteDays(in: folder, olderThan: current.deleteAfterDays, permanently: current.deletePermanently)
            if count > 0 { DaylapseLog.write("Retention removed \(count) day folders") }
        }
    }

    @MainActor @objc private func toggleCapture() {
        captureEngine.toggle()
        toggleItem.title = captureEngine.isStarted ? "Stop Screenshots" : "Start Screenshots"
    }

    @MainActor private func renderStatus(_ text: String) {
        statusLine.title = text
        // One thing shows at a time: the app icon when idle, a symbol when paused or blocked, else the countdown.
        let button = statusItem.button
        button?.title = ""
        if text == "○" {
            button?.image = menuBarImage
        } else if text == AppRules.Pause.notAllowed.statusText {
            button?.image = Self.symbol("nosign")
        } else if text.hasPrefix("⏸") {
            button?.image = Self.symbol("pause.fill")
        } else {
            button?.image = nil
            button?.title = text.hasPrefix("● ") ? String(text.dropFirst(2)) : text
        }
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        image?.isTemplate = true
        return image
    }

    @MainActor @objc private func exportToday() {
        let day = Storage.dayName(for: Date())
        exportItem.title = "Exporting…"
        exportItem.isEnabled = false
        let fps = SettingsStore.shared.settings.exportFPS
        DispatchQueue.global().async {
            let result = Result { try Exporter.export(day: day, fps: fps, in: Storage.screenshotsFolder) }
            DispatchQueue.main.async { [weak self] in
                self?.exportItem.title = "Export Today as Video"
                self?.exportItem.isEnabled = true
                Self.finishExport(result)
            }
        }
    }

    @MainActor static func finishExport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            DaylapseLog.write("Exported \(urls.map(\.lastPathComponent).joined(separator: ", "))")
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .failure(let error):
            DaylapseLog.write("Export failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func openScreenshotsFolder() {
        NSWorkspace.shared.open(Storage.screenshotsFolder)
    }

    @MainActor @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showSettings()
        if let window = settingsWindowController?.window, settingsObservers.isEmpty {
            let center = NotificationCenter.default
            for (name, active) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false),
                                   (NSWindow.willCloseNotification, false)] {
                settingsObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.captureEngine.isSettingsActive = active }
                })
            }
        }
        captureEngine.isSettingsActive = settingsWindowController?.window?.isKeyWindow ?? false
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
        captureEngine.isMenuOpen = true
    }

    @MainActor func menuDidClose(_ menu: NSMenu) {
        captureEngine.isMenuOpen = false
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
            alert.informativeText = "Grant Screenshots Timelapse access in Privacy & Security → Screen Recording, then quit and relaunch Screenshots Timelapse before taking a screenshot."
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
