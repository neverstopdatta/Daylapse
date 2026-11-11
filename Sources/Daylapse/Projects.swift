import AppKit

// A project is a named screenshots folder, so separate pieces of work keep separate day lists.
struct Project: Codable, Hashable, Identifiable {
    var name: String
    var path: String
    var id: String { path }

    var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true) }
}

extension DaylapseSettings {
    // `folderPath` is always the active project's folder.
    var activeIndex: Int? { projects.firstIndex { $0.path == folderPath } }
    var activeProjectName: String { activeIndex.map { projects[$0].name } ?? "Default" }

    private static func sameFolder(_ a: String, _ b: String) -> Bool {
        (a as NSString).expandingTildeInPath == (b as NSString).expandingTildeInPath
    }

    // Keeps the list valid: unique folders, and the active folder always has a project.
    mutating func normalizeProjects() {
        var kept: [Project] = []
        for project in projects where !kept.contains(where: { Self.sameFolder($0.path, project.path) }) { kept.append(project) }
        projects = kept
        if activeIndex == nil {
            projects.insert(Project(name: projects.isEmpty ? "Default" : (folderPath as NSString).lastPathComponent, path: folderPath), at: 0)
        }
    }

    // Returns an error message, or nil once the project is added and made active.
    mutating func addProject(named raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Enter a name." }
        guard !projects.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return "A project called \"\(name)\" already exists."
        }
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let path = "~/Pictures/Screenshots Timelapse - \(safe)"
        guard !projects.contains(where: { Self.sameFolder($0.path, path) }) else { return "That project's folder is already in use." }
        projects.append(Project(name: name, path: path))
        folderPath = path
        return nil
    }

    mutating func selectProject(path: String) {
        if projects.contains(where: { $0.path == path }) { folderPath = path }
    }

    // Only the list entry goes; the screenshots stay on disk.
    mutating func removeActiveProject() {
        guard projects.count > 1, let index = activeIndex else { return }
        projects.remove(at: index)
        folderPath = projects[min(index, projects.count - 1)].path
    }

    // False when another project already uses that folder.
    @discardableResult
    mutating func setActiveFolder(_ path: String) -> Bool {
        guard let index = activeIndex else { return false }
        if projects.enumerated().contains(where: { $0.offset != index && Self.sameFolder($0.element.path, path) }) { return false }
        projects[index].path = path
        folderPath = path
        return true
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
