#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation

final class ProfileFileIO {
    private let paths: AuthPaths
    private let fileManager: FileManager

    init(paths: AuthPaths, fileManager: FileManager) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func ensureDirectories() throws {
        try createDirectoryIfNeeded(paths.codexDirectory)
        try migrateLegacyProfilesIfNeeded()
        try createDirectoryIfNeeded(paths.managerDirectory)
        try createDirectoryIfNeeded(paths.profilesDirectory)
    }

    func listProfiles() throws -> [String] {
        let files = try fileManager.contentsOfDirectory(at: paths.profilesDirectory,
                                                        includingPropertiesForKeys: nil)
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func removeItemIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    func profileURL(for name: String) -> URL {
        paths.profilesDirectory.appendingPathComponent(name).appendingPathExtension("json")
    }

    func readActiveAccountID() -> String? {
        guard fileManager.fileExists(atPath: paths.activeAccountIDFile.path),
              let data = try? Data(contentsOf: paths.activeAccountIDFile),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func writeActiveAccountID(_ accountID: String) throws {
        let data = Data(accountID.utf8)
        try writeSecureAtomically(data: data, to: paths.activeAccountIDFile)
    }

    func clearActiveAccountID() throws {
        try removeItemIfExists(at: paths.activeAccountIDFile)
    }

    func readValidatedAuthFile(at url: URL) throws -> ValidatedAuthFile {
        guard fileManager.fileExists(atPath: url.path) else {
            throw AuthManagerError.ioFailure("File not found: \(url.path)")
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        guard let document = try? decoder.decode(CodexAuthDocument.self, from: data) else {
            throw AuthManagerError.invalidAuthFile(url)
        }

        guard !document.auth_mode.isEmpty,
              !document.tokens.id_token.isEmpty,
              !document.tokens.access_token.isEmpty,
              !document.tokens.refresh_token.isEmpty,
              !document.tokens.account_id.isEmpty else {
            throw AuthManagerError.invalidAuthFile(url)
        }

        return ValidatedAuthFile(rawData: data, document: document)
    }

    func writeSecureAtomically(data: Data, to destination: URL) throws {
        let temp = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".tmp-\(UUID().uuidString)-\(destination.lastPathComponent)")

        guard fileManager.createFile(atPath: temp.path, contents: data,
                                     attributes: [.posixPermissions: NSNumber(value: Int(0o600))]) else {
            throw AuthManagerError.ioFailure("Failed to create temporary auth file")
        }

        do {
            try setFilePermissions(at: temp)
            try renameItem(from: temp, to: destination)
            try setFilePermissions(at: destination)
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
    }

    private func createDirectoryIfNeeded(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            try setDirectoryPermissions(at: url)
        }
    }

    private func migrateLegacyProfilesIfNeeded() throws {
        guard fileManager.fileExists(atPath: paths.legacyProfilesDirectory.path) else {
            return
        }

        try createDirectoryIfNeeded(paths.managerDirectory)
        try createDirectoryIfNeeded(paths.profilesDirectory)

        let legacyFiles = try fileManager.contentsOfDirectory(at: paths.legacyProfilesDirectory,
                                                              includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        for legacyFile in legacyFiles {
            let destination = paths.profilesDirectory.appendingPathComponent(legacyFile.lastPathComponent)
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.copyItem(at: legacyFile, to: destination)
                try setFilePermissions(at: destination)
            }
        }
    }

    private func renameItem(from source: URL, to destination: URL) throws {
        let rc = source.path.withCString { src in
            destination.path.withCString { dst in
                rename(src, dst)
            }
        }
        if rc != 0 {
            throw AuthManagerError.ioFailure("Failed replacing \(destination.path)")
        }
    }

    private func setFilePermissions(at url: URL) throws {
        let rc = url.path.withCString { path in
            chmod(path, S_IRUSR | S_IWUSR)
        }
        if rc != 0 {
            throw AuthManagerError.ioFailure("Failed setting secure permissions on \(url.path)")
        }
    }

    private func setDirectoryPermissions(at url: URL) throws {
        let rc = url.path.withCString { path in
            chmod(path, S_IRUSR | S_IWUSR | S_IXUSR)
        }
        if rc != 0 {
            throw AuthManagerError.ioFailure("Failed setting secure permissions on \(url.path)")
        }
    }
}
