import Foundation

extension ImportSource {
    // MARK: - Static Variables

    /// The person's home folder, where other browsers keep their data, even
    /// when this process runs in a sandbox container of its own.
    static var hostHomeDirectory: URL {
        let fileManager = FileManager.default
        let userName = ProcessInfo.processInfo.environment["USER"] ?? NSUserName()
        return resolvedHomeDirectory(
            currentHome: fileManager.homeDirectoryForCurrentUser,
            accountHome: fileManager.homeDirectory(forUser: userName)
        )
    }

    // MARK: - Variables

    /// Where the browser keeps its data in the person's home folder.
    var defaultDataDirectory: URL {
        dataDirectory(in: Self.hostHomeDirectory)
    }

    // MARK: - Actions - Folders

    static func resolvedHomeDirectory(currentHome: URL, accountHome: URL?) -> URL {
        accountHome ?? currentHome
    }

    /// Where the browser keeps its data in `homeDirectory`.
    func dataDirectory(in homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(dataFolder, isDirectory: true)
    }

    /// What the browser keeps in `directory`, as the core finds it; nothing
    /// when the core cannot look.
    func importData(in directory: URL) -> ImportData {
        (try? CrestCore.answer(FindImportData(source: self, folder: directory.path)))
            ?? ImportData(profiles: [], passwordStores: [])
    }
}
