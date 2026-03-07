import Foundation

final class CodexSkillsProvider: @unchecked Sendable {
    private let homeDirectory: URL
    private let fileManager: FileManager

    init(homeDirectory: URL,
         fileManager: FileManager = .default) {
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    func installedSkillNames() -> [String] {
        let skillsDirectory = homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("skills", isDirectory: true)

        guard let children = try? fileManager.contentsOfDirectory(at: skillsDirectory,
                                                                  includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles]) else {
            return []
        }

        var names: [String] = []
        for child in children {
            let name = child.lastPathComponent
            guard name != ".system" else {
                continue
            }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let skillFile = child.appendingPathComponent("SKILL.md")
            guard fileManager.fileExists(atPath: skillFile.path) else {
                continue
            }
            names.append(name)
        }

        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
