import AppKit
import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    @Binding var settings: DaylapseSettings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
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
            LabeledContent("Start/Stop shortcut") {
                ShortcutRecorder(shortcut: $settings.shortcut)
            }
        }
        .formStyle(.grouped)
    }
}

struct CaptureTab: View {
    @Binding var settings: DaylapseSettings
    var body: some View {
        Form {
            DurationField(title: "Interval", seconds: $settings.intervalSeconds, range: 1...3600, zeroMeansOff: false)
            Toggle("Show pointer", isOn: $settings.showPointer)
            DurationField(title: "Pause when idle", seconds: $settings.pauseWhenIdleSeconds, range: 0...7200, zeroMeansOff: true,
                          note: "0 turns idle pausing off")
            Toggle("Pause when screen is locked", isOn: $settings.pauseWhenLocked)
            Toggle("Pause timer while the menu is open", isOn: $settings.pauseWhenMenuOpen)
            Picker("Displays", selection: $settings.displays) {
                Text("All displays").tag("all")
                Text("Main display only").tag("main")
            }
            Toggle("Half size on Retina", isOn: $settings.halfSizeOnRetina)
            LabeledContent("JPEG quality \(Int(settings.jpegQuality * 100))%") {
                Slider(value: $settings.jpegQuality, in: 0.3...1.0)
            }
        }
        .formStyle(.grouped)
    }
}

struct StorageTab: View {
    @Binding var settings: DaylapseSettings
    @State private var usedBytes: Int64 = 0

    var body: some View {
        Form {
            LabeledContent("Folder") {
                Text(settings.folderPath).lineLimit(1).truncationMode(.middle)
            }
            HStack {
                Button("Change…", action: chooseFolder)
                Button("Show in Finder") { NSWorkspace.shared.open(Storage.screenshotsFolder) }
            }
            LabeledContent("Used", value: ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file))
            Button("Delete All…", role: .destructive, action: deleteAll)
            Picker("Delete older than", selection: $settings.deleteAfterDays) {
                Text("Never").tag(0)
                ForEach([7, 30, 90, 365], id: \.self) { Text("\($0) days").tag($0) }
            }
            Toggle("Delete permanently (skip Trash)", isOn: $settings.deletePermanently)
            Picker("Minimum free space", selection: $settings.minFreeSpaceGB) {
                ForEach([1, 2, 5, 10, 20], id: \.self) { Text("\($0) GB").tag($0) }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshSize)
        .onChange(of: settings.folderPath) { _, _ in refreshSize() }
    }

    private func refreshSize() {
        let folder = Storage.screenshotsFolder
        DispatchQueue.global().async {
            let size = Storage.usedBytes(in: folder)
            DispatchQueue.main.async { usedBytes = size }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = Storage.screenshotsFolder.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.folderPath = (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func deleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all screenshots?"
        alert.informativeText = settings.deletePermanently
            ? "All day folders will be deleted permanently. Exported videos are kept."
            : "All day folders will be moved to the Trash. Exported videos are kept."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let count = Storage.deleteDays(in: Storage.screenshotsFolder, olderThan: nil, permanently: settings.deletePermanently)
        DaylapseLog.write("Delete All removed \(count) day folders")
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
        VStack(spacing: 4) {
            LabeledContent(title) {
                HStack(spacing: 6) {
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
            }
            HStack {
                if let note { Text(note) }
                Spacer()
                Text(caption)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
private struct RepeatButton: View {
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
