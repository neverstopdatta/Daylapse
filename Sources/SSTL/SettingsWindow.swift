import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable {
    case general, capture, apps, storage, timelapse

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .apps: "square.grid.2x2"
        case .storage: "internaldrive"
        case .timelapse: "film"
        }
    }
}

// Lets the menu open Settings on a given tab.
@MainActor
@Observable
final class SettingsTabSelection {
    var tab = SettingsTab.general
}

@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    private var clickMonitor: Any?
    private let selection: SettingsTabSelection

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        let selection = SettingsTabSelection()
        window.contentView = NSHostingView(rootView: SettingsWindowView(selection: selection))
        self.init(window: window, selection: selection)
        // Icon tabs in the toolbar, like System Settings and most Mac apps; the window title follows the tab.
        let toolbar = NSToolbar(identifier: "SettingsTabs")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .preference
        apply(.general)
        // Clicking outside a text field ends editing.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak window] event in
            if let window, event.window === window,
               let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
               !editor.bounds.contains(editor.convert(event.locationInWindow, from: nil)) {
                // Resign before the click is delivered so it can focus another field in one go.
                window.makeFirstResponder(nil)
            }
            return event
        }
    }

    private init(window: NSWindow, selection: SettingsTabSelection) {
        self.selection = selection
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply(_ tab: SettingsTab) {
        selection.tab = tab
        window?.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)
        window?.title = tab.title
    }

    @objc private func selectTab(_ item: NSToolbarItem) {
        if let tab = SettingsTab(rawValue: item.itemIdentifier.rawValue) { apply(tab) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { identifiers }
    private var identifiers: [NSToolbarItem.Identifier] { SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) } }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                             willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = SettingsTab(rawValue: itemIdentifier.rawValue) else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        item.target = self
        item.action = #selector(selectTab(_:))
        return item
    }

    func showSettings(tab: SettingsTab?) {
        if let tab { apply(tab) }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsWindowView: View {
    @Bindable var selection: SettingsTabSelection
    @State private var settings = SettingsStore.shared.settings
    // The last value this window wrote, so its own save is not echoed back over newer edits.
    @State private var lastSaved: SSTLSettings?

    var body: some View {
        Group {
            switch selection.tab {
            case .general: GeneralTab(settings: $settings)
            case .capture: CaptureTab(settings: $settings)
            case .apps: appsTab
            case .storage: StorageTab(settings: $settings)
            case .timelapse: TimelapseTab(settings: $settings)
            }
        }
        .frame(minWidth: 520, minHeight: 390)
        .onChange(of: settings) { _, newSettings in
            lastSaved = newSettings
            do {
                try SettingsStore.shared.save(newSettings)
            } catch {
                SSTLLog.write("Could not save settings: \(error.localizedDescription)")
            }
        }
        // The menu's block item saves directly, so keep this copy current.
        .onChange(of: SettingsStore.shared.settings) { _, newSettings in
            guard newSettings != lastSaved else { return }
            settings = newSettings
        }
    }

    private var appsTab: some View {
        Form {
            Section {
                Picker("Capture", selection: $settings.appMode) {
                    Text("Everything except…").tag("block")
                    Text("Only…").tag("allow")
                }
            }

            Section(settings.appMode == "block" ? "Blocked apps" : "Allowed apps") {
                if activeApps.isEmpty {
                    Text("No apps added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeApps) { app in
                        HStack(spacing: 10) {
                            Image(nsImage: icon(for: app))
                                .resizable()
                                .frame(width: 28, height: 28)
                            Text(app.name)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                remove(app)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(app.name)")
                        }
                    }
                }
                HStack {
                    Spacer()
                    Menu("Add App") {
                        let apps = runningApps
                        if apps.isEmpty {
                            Text("No running apps")
                        } else {
                            ForEach(apps) { app in
                                Button(app.name) { add(app) }
                            }
                        }
                        Divider()
                        Button("Choose from Applications…", action: addAppFromDisk)
                    }
                    .fixedSize()
                }
            }

            Section("Show in screenshots") {
                Toggle("Wallpaper", isOn: $settings.showWallpaper)
                if !settings.showWallpaper {
                    ColorPicker("Background colour", selection: Binding(
                        get: { Color(hex: settings.backgroundHex) },
                        set: { settings.backgroundHex = $0.hexString }
                    ), supportsOpacity: false)
                }
                Toggle("Desktop icons", isOn: $settings.showDesktopIcons)
                Toggle("Notifications", isOn: $settings.showNotifications)
            }
        }
        .formStyle(.grouped)
    }

    private var activeApps: [AppRuleEntry] {
        settings.appMode == "block" ? settings.blockedApps : settings.allowedApps
    }

    private var runningApps: [AppRuleEntry] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return AppRuleEntry(bundleID: bundleID, name: app.localizedName ?? bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func addAppFromDisk() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        add(AppRuleEntry(bundleID: bundleID, name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                         ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                         ?? url.deletingPathExtension().lastPathComponent))
    }

    private func add(_ app: AppRuleEntry) {
        if settings.appMode == "block" {
            guard !settings.blockedApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
            settings.blockedApps.append(app)
        } else {
            guard !settings.allowedApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
            settings.allowedApps.append(app)
        }
    }

    private func remove(_ app: AppRuleEntry) {
        if settings.appMode == "block" {
            settings.blockedApps.removeAll { $0.bundleID == app.bundleID }
        } else {
            settings.allowedApps.removeAll { $0.bundleID == app.bundleID }
        }
    }

    private func icon(for app: AppRuleEntry) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }
}

private struct TimelapseTab: View {
    @Binding var settings: SSTLSettings
    @State private var days: [Exporter.Day] = []
    @State private var selected: Set<String> = []
    @State private var exporting = false
    @State private var merge = false
    @State private var showSessionNote = false
    @AppStorage("exportNewestFirst") private var newestFirst = true
    @State private var job: ExportJob?
    @State private var progress = 0.0

    private let sessionNote = "These days aren't consecutive.\nCheck they're from the same session."
    private var mergeActive: Bool { merge && selected.count > 1 }
    private var shownDays: [Exporter.Day] { newestFirst ? days : days.reversed() }

    var body: some View {
        Form {
            Section {
                Picker("Project", selection: $settings.activeProject) {
                    ForEach(SettingsStore.shared.projects, id: \.self) { Text($0).tag($0) }
                }
            }
            Section {
                IntField(title: "Speed", value: $settings.exportFPS, range: 1...60, unit: "fps", caption: lengthText)
                HStack {
                    Text(selected.isEmpty ? "Select the days to export." : "\(selected.count) selected")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if exporting {
                        ProgressView(value: progress).frame(width: 120)
                        Button("Cancel") { job?.cancel() }
                    } else {
                        Picker("Format", selection: $settings.exportFormat) {
                            Text("MP4").tag("mp4")
                            Text("GIF").tag("gif")
                        }
                        .labelsHidden().fixedSize()
                        Button("Export") { export() }
                            .disabled(selected.isEmpty)
                    }
                }
                if settings.exportFormat == "gif" {
                    Picker("GIF size", selection: $settings.gifMaxSide) {
                        Text("Small (480 px)").tag(480)
                        Text("Medium (720 px)").tag(720)
                        Text("Large (1080 px)").tag(1080)
                    }
                    Picker("GIF colours", selection: $settings.gifColors) {
                        Text("256").tag(256)
                        Text("128").tag(128)
                        Text("64").tag(64)
                    }
                    Toggle("Dither gradients", isOn: $settings.gifDither)
                }
                HStack(spacing: 6) {
                    Toggle("Combine selected days into one video", isOn: $merge)
                        .toggleStyle(.checkbox)
                        .disabled(selected.count < 2)
                    Spacer()
                    // Fixed-size slot so the notice appears without moving anything.
                    Button { showSessionNote.toggle() } label: {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                    .help(sessionNote)
                    .popover(isPresented: $showSessionNote, arrowEdge: .bottom) {
                        Text(sessionNote).fixedSize().padding(10)
                    }
                    .opacity(merge && selected.count > 1 && !consecutive ? 1 : 0)
                    .disabled(!(merge && selected.count > 1 && !consecutive))
                }
            }
            Section {
                HStack {
                    Toggle("Select all", isOn: Binding(
                        get: { !days.isEmpty && selected.count == days.count },
                        set: { selected = $0 ? Set(days.map(\.name)) : [] }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(days.isEmpty)
                    Spacer()
                    Picker("Order", selection: $newestFirst) {
                        Text("Newest first").tag(true)
                        Text("Oldest first").tag(false)
                    }
                    .labelsHidden().fixedSize()
                }
                if days.isEmpty {
                    Text("No days captured yet").foregroundStyle(.secondary)
                }
                ForEach(shownDays) { day in
                    Toggle(isOn: Binding(
                        get: { selected.contains(day.name) },
                        set: { if $0 { selected.insert(day.name) } else { selected.remove(day.name) } }
                    )) {
                        HStack {
                            Text(day.name)
                            Spacer()
                            Text("\(day.frameCount) screenshots").foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            } header: {
                HStack {
                    Text("Days")
                    Spacer()
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Refresh the list of days")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reload() }
        // New screenshots arrive while the window is closed, so look again when the app comes forward.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
        .onChange(of: settings.folderPath) { _, _ in
            selected = []
            reload()
        }
    }

    private var consecutive: Bool {
        let dates = selected.sorted().compactMap(Storage.dayDate)
        let calendar = Calendar.current
        return zip(dates, dates.dropFirst()).allSatisfy { calendar.dateComponents([.day], from: $0, to: $1).day == 1 }
    }

    // Separate videos add up to the total; combined days make a single video.
    private var lengthText: String {
        let counts = days.filter { selected.contains($0.name) }.map(\.videoFrames)
        let frames = counts.reduce(0, +)
        guard frames > 0 else { return "Select days to see the length" }
        let seconds = Int((Double(frames) / Double(settings.exportFPS)).rounded(.up))
        return "\(DurationField.describe(seconds))\(selected.count > 1 && !mergeActive ? " in total" : "")"
    }

    private func reload() {
        let folder = settings.folderURL
        days = Exporter.days(in: folder)
        selected = selected.filter { name in days.contains { $0.name == name } }
    }

    private func export() {
        exporting = true
        progress = 0
        let newJob = ExportJob()
        job = newJob
        let batches = mergeActive ? [selected.sorted()] : selected.sorted().map { [$0] }
        let fps = settings.exportFPS
        let format = settings.exportFormat
        let gifOptions = GIFOptions(maxSide: settings.gifMaxSide, colors: settings.gifColors, dither: settings.gifDither)
        let folder = settings.folderURL
        DispatchQueue.global().async {
            let result = Result {
                try Exporter.export(batches: batches, fps: fps, format: format, gif: gifOptions, in: folder, job: newJob) { value in
                    DispatchQueue.main.async { progress = value }
                }
            }
            DispatchQueue.main.async {
                exporting = false
                job = nil
                if case .failure(let error) = result, case ExportError.cancelled = error { return }
                AppDelegate.finishExport(result)
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(digits, radix: 16) ?? 0
        self.init(.sRGB, red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int(round(color.redComponent * 255)),
                      Int(round(color.greenComponent * 255)), Int(round(color.blueComponent * 255)))
    }
}
