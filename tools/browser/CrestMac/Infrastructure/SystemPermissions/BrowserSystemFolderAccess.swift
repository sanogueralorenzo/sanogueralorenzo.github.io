import AppKit

@MainActor
final class BrowserSystemFolderAccess {
    private let preferences: BrowserPlatformDownloadPreferences
    private var checkedFolders: [UUID: (name: String, status: BrowserSystemPermissionStatus)] = [:]

    init(preferences: BrowserPlatformDownloadPreferences = .shared) {
        self.preferences = preferences
    }

    func status(spaceID: UUID?) -> BrowserSystemPermissionStatus {
        guard let spaceID else { return .init(state: .unavailable) }
        if preferences.asksWhereToSave(for: spaceID) {
            return .init(
                state: .chooseEachTime, detail: String(localized: "You approve each destination in the Save dialog."))
        }
        let name = preferences.directoryDisplayName(for: spaceID) ?? String(localized: "Downloads")
        guard let checked = checkedFolders[spaceID], checked.name == name else {
            return .init(
                state: .notChecked,
                detail: String(
                    localized: "Download folder: \(name). Check Access verifies that Crest can save a file there."))
        }
        return checked.status
    }

    func check(spaceID: UUID) async throws {
        let name = preferences.directoryDisplayName(for: spaceID) ?? String(localized: "Downloads")
        do {
            try await validate(spaceID: spaceID)
            checkedFolders[spaceID] = (
                name, .init(state: .allowed, detail: String(localized: "Crest can save files in \(name)."))
            )
        } catch {
            checkedFolders[spaceID] = (
                name,
                .init(
                    state: .blocked,
                    detail: String(
                        localized:
                            "Crest could not save to \(name). Choose the folder again or review Files & Folders in System Settings."
                    ))
            )
            throw error
        }
    }

    func chooseFolder(spaceID: UUID) async throws {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Allow Access to a Download Folder")
        panel.prompt = String(localized: "Use Folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let url = panel.url else { return }
        try await Task.detached { try Self.validateDirectory(url) }.value
        try preferences.rememberDirectory(url, for: spaceID)
        preferences.setAsksWhereToSave(false, for: spaceID)
        try await check(spaceID: spaceID)
    }

    private func validate(spaceID: UUID) async throws {
        let hasCustomFolder = preferences.directoryDisplayName(for: spaceID) != nil
        let customFolder = preferences.directoryURL(for: spaceID)
        guard !hasCustomFolder || customFolder != nil else {
            throw CocoaError(.fileReadNoPermission)
        }
        guard
            let directory = customFolder
                ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        else { throw CocoaError(.fileNoSuchFile) }
        try await Task.detached { try Self.validateDirectory(directory) }.value
    }

    /// An explicit check verifies actual write access, including macOS privacy
    /// restrictions, without inspecting or changing existing files.
    nonisolated static func validateDirectory(_ directory: URL) throws {
        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        let probe = directory.appending(path: ".crest-access-check-\(UUID())")
        try Data().write(to: probe, options: .withoutOverwriting)
        try FileManager.default.removeItem(at: probe)
    }
}
