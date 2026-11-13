import AppKit
import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    @Binding var settings: SSTLSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var notificationsDenied = false

    var body: some View {
        Form {
            Section {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        loginError = nil
                    } catch {
                        loginError = error.localizedDescription
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            if let loginError {
                Text(loginError).foregroundStyle(.red)
            }
            }
            Section {
                LabeledContent("Start/Stop shortcut") {
                    ShortcutRecorder(shortcut: $settings.shortcut)
                }
                Toggle(isOn: $settings.notifyOnToggle) {
                    HStack(spacing: 4) {
                        Text("Show a notification")
                        InfoButton("Shows a notification when starting or stopping capture with the shortcut.")
                    }
                }
                .onChange(of: settings.notifyOnToggle) { _, on in
                    guard on else { return }
                    notificationsDenied = false
                    ToggleFeedback.requestNotifications { granted in
                        notificationsDenied = !granted
                        if !granted { settings.notifyOnToggle = false }
                    }
                }
                if notificationsDenied {
                    Text("Allow notifications for Screenshots Timelapse in System Settings > Notifications.")
                        .foregroundStyle(.red)
                }
                Toggle(isOn: $settings.soundOnToggle) {
                    HStack(spacing: 4) {
                        Text("Play a sound")
                        InfoButton("Plays a sound when starting or stopping capture with the shortcut.")
                    }
                }
                if settings.soundOnToggle {
                    soundPicker("Start sound", selection: $settings.startSound)
                    soundPicker("Stop sound", selection: $settings.stopSound)
                }
            }
            Section {
                Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
                HStack {
                    Text("Version \(UpdateChecker.currentVersion)").foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for Updates…") { UpdateChecker.check(userInitiated: true) }
                }
            }
        }
        .formStyle(.grouped)
    }

    // Choosing a sound plays it, so you hear what you pick.
    private func soundPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ToggleFeedback.soundNames, id: \.self) { Text($0).tag($0) }
        }
        .onChange(of: selection.wrappedValue) { _, name in ToggleFeedback.play(name) }
    }
}

// The small ⓘ macOS uses for a longer explanation: opens a popover on click, tooltip on hover.
struct InfoButton: View {
    let text: String
    @State private var shown = false

    init(_ text: String) { self.text = text }

    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(text)
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(text).frame(width: 240, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(10)
            }
    }
}

struct CaptureTab: View {
    @Binding var settings: SSTLSettings
    @State private var connectedDisplays = Displays.connected()

    var body: some View {
        Form {
            Section {
                DurationField(title: "Interval", seconds: $settings.intervalSeconds, range: 1...3600, zeroMeansOff: false)
                Toggle("Resume countdown after stopping", isOn: $settings.resumeCountdown)
                Toggle("Capture immediately on start", isOn: $settings.captureOnStart)
                Toggle("Show pointer", isOn: $settings.showPointer)
            }
            Section {
            DurationField(title: "Pause when idle", seconds: $settings.pauseWhenIdleSeconds, range: 0...7200, zeroMeansOff: true,
                          note: "0 turns idle pausing off")
            Toggle("Pause when screen is locked", isOn: $settings.pauseWhenLocked)
            Toggle("Pause while menu is open", isOn: $settings.pauseWhenMenuOpen)
            }
            Section {
            Picker("Displays", selection: $settings.displays) {
                Text("All displays").tag("all")
                Text("Main display (follows primary)").tag("main")
                Divider()
                ForEach(connectedDisplays, id: \.key) { Text($0.name).tag($0.key) }
                if !["all", "main"].contains(settings.displays), !connectedDisplays.contains(where: { $0.key == settings.displays }) {
                    Text("Disconnected display").tag(settings.displays)
                }
            }
            Toggle("Half size on Retina", isOn: $settings.halfSizeOnRetina)
            Picker("Format", selection: $settings.imageFormat) {
                Text("JPEG").tag("jpeg")
                if Screenshotter.heicAvailable { Text("HEIC").tag("heic") }
                Text("PNG").tag("png")
            }
            if settings.imageFormat != "png" {
                LabeledContent("Quality \(Int(settings.jpegQuality * 100))%") {
                    Slider(value: $settings.jpegQuality, in: 0.3...1.0)
                }
            }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            connectedDisplays = Displays.connected()
        }
    }
}

struct StorageTab: View {
    @Binding var settings: SSTLSettings
    @State private var usedBytes: Int64 = 0
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool
    // Folder names can't contain "/", so this tag never clashes with a project.
    private static let newProjectTag = "/new"

    var body: some View {
        Form {
            Section {
            Picker("Project", selection: Binding(
                get: { settings.activeProject },
                set: { picked in
                    if picked == Self.newProjectTag {
                        DispatchQueue.main.async(execute: newProject)
                    } else {
                        settings.activeProject = picked
                    }
                }
            )) {
                ForEach(SettingsStore.shared.projects, id: \.self) { Text($0).tag($0) }
                Divider()
                Text("New Project…").tag(Self.newProjectTag)
            }
            TextField("Name", text: $nameDraft)
                .focused($nameFocused)
                .onSubmit(commitName)
            LabeledContent("Location") {
                HStack {
                    Text(settings.rootPath).lineLimit(1).truncationMode(.middle)
                    Button("Change…", action: chooseRoot)
                }
            }
            LabeledContent("Used") {
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file))
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: settings.folderURL, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(settings.folderURL)
                    }
                }
            }
            }
            Section {
            HStack {
                Spacer()
                Button("Delete All Screenshots…", role: .destructive, action: deleteAll)
                Button("Remove Project…", role: .destructive, action: removeProject)
                    .disabled(SettingsStore.shared.projects.count < 2)
            }
            }
            Section {
            Picker("Delete older than", selection: $settings.deleteAfterDays) {
                Text("Never").tag(0)
                ForEach([7, 30, 90, 365], id: \.self) { Text("\($0) days").tag($0) }
            }
            Toggle("Delete permanently (skip Trash)", isOn: $settings.deletePermanently)
            }
            Section {
            Picker("Minimum free space", selection: $settings.minFreeSpaceGB) {
                ForEach([1, 2, 5, 10, 20], id: \.self) { Text("\($0) GB").tag($0) }
            }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            nameDraft = settings.activeProject
            refreshSize()
        }
        .onChange(of: settings.folderPath) { _, _ in
            nameDraft = settings.activeProject
            refreshSize()
        }
        .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
    }

    // Reads the folder from this tab's settings (not Storage, which updates a moment later)
    // and ignores a result if the project changed meanwhile.
    private func refreshSize() {
        let folder = settings.folderURL
        usedBytes = 0
        DispatchQueue.global().async {
            let size = Storage.usedBytes(in: folder)
            DispatchQueue.main.async { if folder == settings.folderURL { usedBytes = size } }
        }
    }

    private func commitName() {
        if let error = settings.renameActiveProject(to: nameDraft) { ProjectPrompt.showError(error) }
        nameDraft = settings.activeProject
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Each folder inside the chosen folder is a project."
        panel.prompt = "Choose"
        panel.directoryURL = settings.rootURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Day folders mean a project folder was picked instead of the folder holding the projects.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        if names.contains(where: { Storage.dayDate($0) != nil }) {
            ProjectPrompt.showError("That folder holds screenshots. Choose the folder that contains your project folders.")
            return
        }
        settings.rootPath = (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func newProject() {
        guard let name = ProjectPrompt.askName() else { return }
        if let error = settings.addProject(named: name) { ProjectPrompt.showError(error) }
    }

    private func removeProject() {
        let alert = NSAlert()
        alert.messageText = "Remove \"\(settings.activeProject)\"?"
        alert.informativeText = settings.deletePermanently
            ? "Its folder, including screenshots and exported videos, will be deleted permanently."
            : "Its folder, including screenshots and exported videos, will be moved to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let error = settings.removeActiveProject() { ProjectPrompt.showError(error) }
    }

    private func deleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all screenshots in \"\(settings.activeProject)\"?"
        alert.informativeText = settings.deletePermanently
            ? "All day folders will be deleted permanently. Exported videos are kept."
            : "All day folders will be moved to the Trash. Exported videos are kept."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let count = Storage.deleteDays(in: settings.folderURL, olderThan: nil, permanently: settings.deletePermanently)
        SSTLLog.write("Delete All removed \(count) day folders")
        refreshSize()
    }
}

// A number plus a seconds/minutes unit, with the resulting duration spelled out underneath.
struct DurationField: View {
    private enum Unit: Double, CaseIterable {
        case seconds = 1, minutes = 60
        var label: String { self == .seconds ? "seconds" : "minutes" }
    }

    let title: String
    @Binding var seconds: Int
    let range: ClosedRange<Int>
    let zeroMeansOff: Bool
    var note: String?
    @State private var text = ""
    @State private var unit = Unit.seconds
    @FocusState private var focused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(caption).font(.caption).foregroundStyle(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .focused($focused)
                .onSubmit(commit)
            VStack(spacing: 0) {
                RepeatButton(systemImage: "chevron.up") { step(1) }
                RepeatButton(systemImage: "chevron.down") { step(-1) }
            }
            Picker("", selection: $unit) {
                ForEach(Unit.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 100)
        }
        .onAppear(perform: load)
        .onChange(of: focused) { _, isFocused in
            if isFocused { startKeyMonitor() } else { stopKeyMonitor(); commit() }
        }
        .onDisappear(perform: stopKeyMonitor)
        .onChange(of: unit) { _, _ in text = Self.format(Double(seconds) / unit.rawValue) }
        .onChange(of: seconds) { _, _ in if !focused { text = Self.format(Double(seconds) / unit.rawValue) } }
    }

    private var caption: String {
        let typed = Double(text.replacingOccurrences(of: ",", with: ".")) ?? Double(seconds) / unit.rawValue
        let value = clamp(typed * unit.rawValue)
        return value == 0 && zeroMeansOff ? "Off" : Self.describe(value)
    }

    private func load() {
        unit = seconds >= 60 && seconds % 60 == 0 ? .minutes : .seconds
        text = Self.format(Double(seconds) / unit.rawValue)
    }

    private func commit() {
        if let typed = Double(text.replacingOccurrences(of: ",", with: ".")) {
            seconds = clamp(typed * unit.rawValue)
        }
        text = Self.format(Double(seconds) / unit.rawValue)
    }

    // A key monitor sees auto-repeat events, which the text field's own handling swallows.
    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 126 || event.keyCode == 125 else { return event }
            step(event.keyCode == 126 ? 1 : -1)
            return nil
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // One unit per step, applied straight away.
    private func step(_ direction: Int) {
        commit()
        seconds = clamp(Double(seconds) + Double(direction) * unit.rawValue)
        text = Self.format(Double(seconds) / unit.rawValue)
    }

    private func clamp(_ value: Double) -> Int {
        min(max(Int(value.rounded()), range.lowerBound), range.upperBound)
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    // 90 -> "1m 30s", 7200 -> "2h"
    static func describe(_ total: Int) -> String {
        let hours = total / 3600, minutes = total % 3600 / 60, secs = total % 60
        let parts = [(hours, "h"), (minutes, "m"), (secs, "s")].filter { $0.0 > 0 }.map { "\($0.0)\($0.1)" }
        return parts.isEmpty ? "0s" : parts.joined(separator: " ")
    }
}

// Steps once on press, then repeats at the system key-repeat delay and rate while held.
struct RepeatButton: View {
    let systemImage: String
    let action: () -> Void
    @State private var timer: Timer?
    @State private var pressed = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 8, weight: .bold))
            .frame(width: 18, height: 12)
            .background(pressed ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { begin() } }
                .onEnded { _ in end() })
            .onDisappear(perform: end)
    }

    private func begin() {
        pressed = true
        action()
        let delay = Timer(timeInterval: max(0.2, NSEvent.keyRepeatDelay), repeats: false) { _ in
            Task { @MainActor in
                guard pressed else { return }
                let repeater = Timer(timeInterval: max(0.03, NSEvent.keyRepeatInterval), repeats: true) { _ in
                    Task { @MainActor in action() }
                }
                RunLoop.main.add(repeater, forMode: .common)
                timer = repeater
            }
        }
        RunLoop.main.add(delay, forMode: .common)
        timer = delay
    }

    private func end() {
        pressed = false
        timer?.invalidate()
        timer = nil
    }
}

// A whole-number field with up/down buttons and arrow-key stepping, clamped to a range.
struct IntField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String
    // Shown left of the field; the allowed range when nil.
    var caption: String?
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer()
            Text(caption ?? "\(range.lowerBound)–\(range.upperBound)").font(.caption).foregroundStyle(.secondary)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .focused($focused)
                .onSubmit(commit)
            VStack(spacing: 0) {
                RepeatButton(systemImage: "chevron.up") { step(1) }
                RepeatButton(systemImage: "chevron.down") { step(-1) }
            }
            Text(unit).frame(width: 30, alignment: .leading)
        }
        .onAppear { text = String(value) }
        .onChange(of: focused) { _, isFocused in
            if isFocused { startKeyMonitor() } else { stopKeyMonitor(); commit() }
        }
        .onChange(of: value) { _, _ in if !focused { text = String(value) } }
        .onDisappear(perform: stopKeyMonitor)
    }

    private func commit() {
        if let typed = Int(text) { value = min(max(typed, range.lowerBound), range.upperBound) }
        text = String(value)
    }

    private func step(_ direction: Int) {
        commit()
        value = min(max(value + direction, range.lowerBound), range.upperBound)
        text = String(value)
    }

    // A key monitor sees auto-repeat events, which the text field's own handling swallows.
    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 126 || event.keyCode == 125 else { return event }
            step(event.keyCode == 126 ? 1 : -1)
            return nil
        }
    }

    private func stopKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
