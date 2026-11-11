import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController {
    private var clickMonitor: Any?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SSTL Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsWindowView())
        self.init(window: window)
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

    func showSettings() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsWindowView: View {
    @State private var settings = SettingsStore.shared.settings
    // The last value this window wrote, so its own save is not echoed back over newer edits.
    @State private var lastSaved: DaylapseSettings?

    var body: some View {
        TabView {
            GeneralTab(settings: $settings)
                .tabItem { Text("General") }
            CaptureTab(settings: $settings)
                .tabItem { Text("Capture") }
            appsTab
                .tabItem { Text("Apps") }
            StorageTab(settings: $settings)
                .tabItem { Text("Storage") }
            TimelapseTab(settings: $settings)
                .tabItem { Text("Timelapse") }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 390)
        .onChange(of: settings) { _, newSettings in
            lastSaved = newSettings
            do {
                try SettingsStore.shared.save(newSettings)
            } catch {
                DaylapseLog.write("Could not save settings: \(error.localizedDescription)")
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
                    Button("Add App…", action: addAppFromDisk)
                    Menu("Add Running App") {
                        let apps = runningApps
                        if apps.isEmpty {
                            Text("No running apps")
                        } else {
                            ForEach(apps) { app in
                                Button(app.name) { add(app) }
                            }
                        }
                    }
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
    @Binding var settings: DaylapseSettings
    @State private var days: [Exporter.Day] = []
    @State private var selected: Set<String> = []
    @State private var exporting = false
    @State private var merge = false
    @State private var showSessionNote = false
    @AppStorage("exportNewestFirst") private var newestFirst = true
    @State private var ffmpeg: (url: URL, custom: Bool)?
    @State private var ffmpegVersion: String?
    @State private var ffmpegProblem: String?
    @State private var misfiled: [(url: URL, day: String)] = []

    private let sessionNote = "These days aren't consecutive.\nCheck they're from the same session."
    private var mergeActive: Bool { merge && selected.count > 1 }
    private var shownDays: [Exporter.Day] { newestFirst ? days : days.reversed() }

    var body: some View {
        Form {
            if ffmpeg == nil { ffmpegSection }
            if !misfiled.isEmpty {
                Section {
                    warning("\(misfiled.count) screenshots are filed under a different day than \"New day starts at\" (Storage tab) expects.")
                    HStack {
                        Spacer()
                        Button("Move them to the right day", action: fixMisfiled)
                    }
                    .listRowBackground(Color.yellow.opacity(0.18))
                }
            }
            Section {
                IntField(title: "Speed", value: $settings.exportFPS, range: 1...60, unit: "fps", caption: lengthText)
                HStack {
                    Text(selected.isEmpty ? "Select the days to export." : "\(selected.count) selected")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { reload() }
                    Button(exporting ? "Exporting…" : "Export") { export() }
                        .disabled(exporting || selected.isEmpty || ffmpeg == nil)
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
            Section("Days") {
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
            }
            if ffmpeg != nil { ffmpegSection }
        }
        .formStyle(.grouped)
        .onAppear {
            reload()
            refreshFFmpeg()
        }
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        }
    }

    @ViewBuilder private var ffmpegSection: some View {
        let missing = ffmpeg == nil
        Section("ffmpeg") {
            if missing {
                warning("ffmpeg is required to export videos and was not found.")
                    .listRowBackground(Color.yellow.opacity(0.18))
                Text("Install it, for example with Homebrew (brew install ffmpeg) or MacPorts (sudo port install ffmpeg), or choose an existing copy.")
                    .font(.caption).foregroundStyle(.secondary)
                    .listRowBackground(Color.yellow.opacity(0.18))
            } else if let ffmpeg {
                LabeledContent(ffmpeg.custom ? "Chosen" : "Auto-detected") {
                    Text(ffmpeg.url.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                if let ffmpegVersion {
                    LabeledContent("Version", value: ffmpegVersion)
                }
            }
            if let ffmpegProblem {
                warning(ffmpegProblem).listRowBackground(Color.yellow.opacity(0.18))
            }
            HStack {
                if missing {
                    Button("Copy Homebrew command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
                    }
                }
                Button("Choose…", action: chooseFFmpeg)
                if !settings.ffmpegPath.isEmpty {
                    Button("Use auto-detect") {
                        settings.ffmpegPath = ""
                        Exporter.customFFmpegPath = ""
                        ffmpegProblem = nil
                        refreshFFmpeg()
                    }
                }
                Button("Check again", action: refreshFFmpeg)
            }
            .listRowBackground(missing ? Color.yellow.opacity(0.18) : nil)
        }
    }

    private func refreshFFmpeg() {
        let found = Exporter.ffmpegLocation()
        ffmpeg = found
        ffmpegVersion = found.flatMap { Exporter.ffmpegVersion(at: $0.url.path) }
        if found != nil, ffmpegVersion == nil {
            ffmpegProblem = "That file did not report an ffmpeg version, so exports may fail."
        }
    }

    private func chooseFFmpeg() {
        let panel = NSOpenPanel()
        panel.message = "Choose the ffmpeg executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard Exporter.ffmpegVersion(at: url.path) != nil else {
            ffmpegProblem = "\(url.lastPathComponent) is not ffmpeg (it did not report a version), so it was not used."
            return
        }
        ffmpegProblem = nil
        settings.ffmpegPath = url.path
        // The setting reaches Exporter on save, so apply it directly for the immediate re-check.
        Exporter.customFFmpegPath = url.path
        refreshFFmpeg()
    }

    private var consecutive: Bool {
        let dates = selected.sorted().compactMap(Storage.dayDate)
        let calendar = Calendar.current
        return zip(dates, dates.dropFirst()).allSatisfy { calendar.dateComponents([.day], from: $0, to: $1).day == 1 }
    }

    // Separate videos add up to the total; combined days make a single video.
    private var lengthText: String {
        let frames = days.filter { selected.contains($0.name) }.map(\.videoFrames).reduce(0, +)
        guard frames > 0 else { return "Select days to see the length" }
        let seconds = Int((Double(frames) / Double(settings.exportFPS)).rounded(.up))
        return "\(DurationField.describe(seconds))\(selected.count > 1 && !mergeActive ? " in total" : "")"
    }

    private func reload() {
        days = Exporter.days(in: Storage.screenshotsFolder)
        selected = selected.filter { name in days.contains { $0.name == name } }
        let folder = Storage.screenshotsFolder
        DispatchQueue.global().async {
            let found = Storage.misfiled(in: folder)
            DispatchQueue.main.async { misfiled = found }
        }
    }

    private func fixMisfiled() {
        let folder = Storage.screenshotsFolder
        let items = misfiled
        DispatchQueue.global().async {
            Storage.refile(items, in: folder)
            DispatchQueue.main.async { reload() }
        }
    }

    private func export() {
        exporting = true
        let chosen = selected.sorted()
        let fps = settings.exportFPS
        let combine = mergeActive
        DispatchQueue.global().async {
            var results: [Result<[URL], Error>] = []
            if combine {
                results.append(Result { try Exporter.export(days: chosen, fps: fps, in: Storage.screenshotsFolder) })
            } else {
                for day in chosen {
                    results.append(Result { try Exporter.export(day: day, fps: fps, in: Storage.screenshotsFolder) })
                }
            }
            DispatchQueue.main.async {
                exporting = false
                for result in results { AppDelegate.finishExport(result) }
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
