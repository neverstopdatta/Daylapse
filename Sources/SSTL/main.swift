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
    private var projectItem: NSMenuItem!

    private lazy var menuBarImage: NSImage? = Self.menuBarIcon()

    private static func menuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        projectItem = NSMenuItem(title: "Project", action: nil, keyEquivalent: "")
        projectItem.submenu = NSMenu()
        menu.addItem(projectItem)
        let folderItem = NSMenuItem(title: "Open Screenshots Folder", action: #selector(openScreenshotsFolder), keyEquivalent: "")
        menu.addItem(folderItem)
        menu.addItem(NSMenuItem(title: "Export Timelapse…", action: #selector(openTimelapseTab), keyEquivalent: ""))
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
                SSTLLog.write("Screenshot failed: \(error.localizedDescription)")
            }
        }, pauseReason: { [weak self] in
            guard let self else { return .notAllowed }
            return self.systemState.pauseReason() ?? self.appRules.pauseReason()
        }, render: { [weak self] text in
            self?.renderStatus(text)
        })
        hotkey = Hotkey { [weak self] in
            Task { @MainActor in self?.performToggle(viaShortcut: true) }
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
        UpdateChecker.checkIfDue()
        let retentionTimer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.runRetention()
                UpdateChecker.checkIfDue()
            }
        }
        RunLoop.main.add(retentionTimer, forMode: .common)
        if !hotkey.register(keyCode: settings.settings.shortcut.keyCode,
                            carbonModifiers: settings.settings.shortcut.carbonModifiers) {
            SSTLLog.write("Global shortcut registration failed")
        }
    }

    @MainActor private func applyToggleShortcut(_ keyCode: UInt32, _ modifiers: UInt32) {
        toggleItem.keyEquivalent = KeyNames.character(for: keyCode) ?? ""
        toggleItem.keyEquivalentModifierMask = KeyNames.menuModifierMask(modifiers)
    }

    @MainActor private func runRetention() {
        let current = SettingsStore.shared.settings
        guard current.deleteAfterDays > 0 else { return }
        let folders = SettingsStore.shared.projects.map { current.rootURL.appendingPathComponent($0, isDirectory: true) }
        DispatchQueue.global(qos: .utility).async {
            var count = 0
            for folder in folders {
                count += Storage.deleteDays(in: folder, olderThan: current.deleteAfterDays, permanently: current.deletePermanently)
            }
            if count > 0 { SSTLLog.write("Retention removed \(count) day folders") }
        }
    }

    @MainActor @objc private func toggleCapture() {
        performToggle(viaShortcut: false)
    }

    // Sound and notification are only for the global shortcut, where there is no menu to show the change.
    @MainActor private func performToggle(viaShortcut: Bool) {
        captureEngine.toggle()
        toggleItem.title = captureEngine.isStarted ? "Stop Screenshots" : "Start Screenshots"
        if viaShortcut { ToggleFeedback.announce(started: captureEngine.isStarted, settings: SettingsStore.shared.settings) }
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

    @MainActor static func finishExport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            SSTLLog.write("Exported \(urls.map(\.lastPathComponent).joined(separator: ", "))")
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        case .failure(let error):
            SSTLLog.write("Export failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func openScreenshotsFolder() {
        try? FileManager.default.createDirectory(at: Storage.screenshotsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Storage.screenshotsFolder)
    }

    @MainActor @objc private func openSettings() {
        showSettings(tab: nil)
    }

    @MainActor @objc private func openTimelapseTab() {
        showSettings(tab: .timelapse)
    }

    @MainActor private func showSettings(tab: SettingsTab?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showSettings(tab: tab)
        if let window = settingsWindowController?.window, settingsObservers.isEmpty {
            let center = NotificationCenter.default
            for (name, active) in [(NSWindow.didBecomeKeyNotification, true), (NSWindow.didResignKeyNotification, false),
                                   (NSWindow.willCloseNotification, false)] {
                settingsObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        if active { SettingsStore.shared.syncWithDisk() }
                        self?.captureEngine.isSettingsActive = active
                    }
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
            SSTLLog.write("Could not update app rule: \(error.localizedDescription)")
        }
    }

    @MainActor func menuWillOpen(_ menu: NSMenu) {
        updateBlockMenuItem()
        SettingsStore.shared.syncWithDisk()
        updateProjectMenu()
        captureEngine.isMenuOpen = true
    }

    @MainActor func menuDidClose(_ menu: NSMenu) {
        captureEngine.isMenuOpen = false
    }

    // A submenu that opens to the side when the item is hovered.
    @MainActor private func updateProjectMenu() {
        let current = SettingsStore.shared.settings
        projectItem.title = "Project: \(current.activeProject)"
        let submenu = projectItem.submenu ?? NSMenu()
        submenu.removeAllItems()
        for project in SettingsStore.shared.projects {
            let item = NSMenuItem(title: project, action: #selector(selectProject(_:)), keyEquivalent: "")
            item.representedObject = project
            item.state = project == current.activeProject ? .on : .off
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        submenu.addItem(NSMenuItem(title: "New Project…", action: #selector(newProject), keyEquivalent: ""))
        projectItem.submenu = submenu
    }

    @MainActor @objc private func selectProject(_ sender: NSMenuItem) {
        guard let project = sender.representedObject as? String else { return }
        var updated = SettingsStore.shared.settings
        updated.activeProject = project
        saveSettings(updated)
    }

    @MainActor @objc private func newProject() {
        guard let name = ProjectPrompt.askName() else { return }
        var updated = SettingsStore.shared.settings
        if let error = updated.addProject(named: name) {
            ProjectPrompt.showError(error)
        } else {
            saveSettings(updated)
        }
    }

    @MainActor private func saveSettings(_ updated: SSTLSettings) {
        do {
            try SettingsStore.shared.save(updated)
        } catch {
            SSTLLog.write("Could not save settings: \(error.localizedDescription)")
        }
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
