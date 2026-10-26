import Foundation

@MainActor
final class BrowserSystemFolderAccess {
    private(set) var status = BrowserSystemPermissionStatus(
        state: .notChecked,
        detail: String(localized: "Check Access verifies that Crest can save files in Downloads."))

    func check() async throws {
        do {
            guard let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }
            try await Task.detached { try Self.validateDirectory(directory) }.value
            status = .init(state: .allowed, detail: String(localized: "Crest can save files in Downloads."))
        } catch {
            status = .init(
                state: .blocked,
                detail: String(
                    localized: "Crest could not save to Downloads. Review Files & Folders in System Settings."))
            throw error
        }
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
