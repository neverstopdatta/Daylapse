import AppKit

// A project is a folder inside the root folder, so renames and deletes in Finder carry over to the app.
enum Projects {
    static let defaultName = "Default"

    // The root's visible subfolders, sorted like Finder.
    static func names(in root: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { name in
            var isDirectory: ObjCBool = false
            return !name.hasPrefix(".")
                && FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // The project to fall back to when the active one is gone: Default if present, else the first one.
    static func fallback(in names: [String]) -> String {
        names.contains(defaultName) ? defaultName : names.first ?? defaultName
    }

    // Returns an error message, or nil when `name` can be used as a project folder.
    static func check(_ name: String, in root: URL, except current: String? = nil) -> String? {
        guard !name.isEmpty else { return "Enter a name." }
        guard !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else {
            return "Project names can't start with a dot or contain / or :."
        }
        let taken = names(in: root).contains { $0 != current && $0.caseInsensitiveCompare(name) == .orderedSame }
        return taken ? "A project called \"\(name)\" already exists." : nil
    }
}

extension SSTLSettings {
    var rootURL: URL { URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath, isDirectory: true) }
    // The active project's folder.
    var folderURL: URL { rootURL.appendingPathComponent(activeProject, isDirectory: true) }
    var folderPath: String { (rootPath as NSString).appendingPathComponent(activeProject) }

    // Creates the project's folder and makes it active. Returns an error message, or nil on success.
    mutating func addProject(named raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = Projects.check(name, in: rootURL) { return error }
        do {
            try FileManager.default.createDirectory(at: rootURL.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
        } catch {
            return error.localizedDescription
        }
        activeProject = name
        return nil
    }

    // Renames the active project's folder. Returns an error message, or nil on success.
    mutating func renameActiveProject(to raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != activeProject else { return nil }
        if let error = Projects.check(name, in: rootURL, except: activeProject) { return error }
        let target = rootURL.appendingPathComponent(name, isDirectory: true)
        // A project without screenshots yet has no folder to move.
        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            activeProject = name
            return nil
        }
        do {
            // A case-only rename goes through a temporary name, since the disk usually ignores case.
            if name.caseInsensitiveCompare(activeProject) == .orderedSame {
                let temporary = rootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.moveItem(at: folderURL, to: temporary)
                try FileManager.default.moveItem(at: temporary, to: target)
            } else {
                try FileManager.default.moveItem(at: folderURL, to: target)
            }
        } catch {
            return error.localizedDescription
        }
        activeProject = name
        return nil
    }

    // Trashes (or deletes) the active project's folder and switches to another project.
    // Returns an error message, or nil on success.
    mutating func removeActiveProject() -> String? {
        // A project without screenshots yet has no folder to delete.
        if FileManager.default.fileExists(atPath: folderURL.path) {
            do {
                if deletePermanently {
                    try FileManager.default.removeItem(at: folderURL)
                } else {
                    try FileManager.default.trashItem(at: folderURL, resultingItemURL: nil)
                }
            } catch {
                return error.localizedDescription
            }
        }
        activeProject = Projects.fallback(in: Projects.names(in: rootURL))
        return nil
    }
}

enum ProjectPrompt {
    @MainActor static func askName() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "New project"
        alert.informativeText = "Each project keeps its screenshots and day list in its own folder."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    @MainActor static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }
}
