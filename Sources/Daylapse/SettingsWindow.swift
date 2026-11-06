import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Daylapse Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsWindowView())
        self.init(window: window)
    }

    func showSettings() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsWindowView: View {
    @State private var settings = SettingsStore.shared.settings

    var body: some View {
        TabView {
            placeholder("General")
                .tabItem { Text("General") }
            captureTab
                .tabItem { Text("Capture") }
            appsTab
                .tabItem { Text("Apps") }
            placeholder("Storage")
                .tabItem { Text("Storage") }
            placeholder("Timelapse")
                .tabItem { Text("Timelapse") }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 390)
        .onChange(of: settings) { _, newSettings in
            do {
                try SettingsStore.shared.save(newSettings)
            } catch {
                DaylapseLog.write("Could not save settings: \(error.localizedDescription)")
            }
        }
        // The menu's block item saves directly, so keep this copy current.
        .onChange(of: SettingsStore.shared.settings) { _, newSettings in
            settings = newSettings
        }
    }

    private var captureTab: some View {
        Form {
            Toggle("Pause timer while the menu is open", isOn: $settings.pauseWhenMenuOpen)
        }
        .formStyle(.grouped)
    }

    private var appsTab: some View {
        Form {
            Picker("Capture", selection: $settings.appMode) {
                Text("Capture everything except…").tag("block")
                Text("Capture only…").tag("allow")
            }

            Section {
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
            } header: {
                Text(settings.appMode == "block" ? "Blocked apps" : "Allowed apps")
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

    private func placeholder(_ title: String) -> some View {
        Form {
            Text("\(title) settings will be available in a later milestone.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
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
