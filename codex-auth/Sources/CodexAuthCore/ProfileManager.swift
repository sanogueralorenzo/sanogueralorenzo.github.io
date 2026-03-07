import Foundation

public final class ProfileManager {
    public let paths: AuthPaths
    private let fileIO: ProfileFileIO
    private let profileService: ProfileService
    private let sessionInvalidator: SessionInvalidator

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                fileManager: FileManager = .default) {
        self.paths = AuthPaths(homeDirectory: homeDirectory)
        self.fileIO = ProfileFileIO(paths: paths, fileManager: fileManager)
        self.profileService = ProfileService(fileIO: fileIO)
        self.sessionInvalidator = SessionInvalidator(fileManager: fileManager)
    }

    public func ensureDirectories() throws {
        try fileIO.ensureDirectories()
    }

    public func listProfiles() throws -> [String] {
        try fileIO.ensureDirectories()
        return try profileService.listProfileNames()
    }

    public func saveProfile(name: String, source: ProfileSource = .current) throws -> String {
        let normalizedName = try profileService.normalizedProfileName(name)
        try fileIO.ensureDirectories()

        let profileURL = fileIO.profileURL(for: normalizedName)
        if fileIO.fileExists(at: profileURL) {
            throw AuthManagerError.duplicateProfileName(existingProfile: normalizedName)
        }

        let currentAuth: ValidatedAuthFile
        do {
            currentAuth = try fileIO.readValidatedAuthFile(at: paths.codexAuthFile)
        } catch {
            throw AuthManagerError.missingCurrentToken(paths.codexAuthFile)
        }

        let payload: ValidatedAuthFile
        switch source {
        case .current:
            payload = currentAuth
        case .path(let path):
            payload = try fileIO.readValidatedAuthFile(at: path)
        }

        try profileService.ensureUniqueProfile(normalizedName: normalizedName, payload: payload)

        try fileIO.writeSecureAtomically(data: payload.rawData, to: profileURL)
        if payload.document.tokens.account_id == currentAuth.document.tokens.account_id {
            try fileIO.writeActiveAccountID(payload.document.tokens.account_id)
        }
        return normalizedName
    }

    public func removeProfile(name: String) throws {
        let normalizedName = try profileService.normalizedProfileName(name)
        let url = fileIO.profileURL(for: normalizedName)
        guard fileIO.fileExists(at: url) else {
            throw AuthManagerError.missingProfile(normalizedName)
        }
        let removed = try fileIO.readValidatedAuthFile(at: url)
        try fileIO.removeItem(at: url)
        if fileIO.readActiveAccountID() == removed.document.tokens.account_id,
           try profileService.profileName(forAccountID: removed.document.tokens.account_id) == nil {
            try fileIO.clearActiveAccountID()
        }
    }

    public func applyProfile(name: String) throws -> SwitchResult {
        let normalizedName = try profileService.normalizedProfileName(name)
        let url = fileIO.profileURL(for: normalizedName)
        guard fileIO.fileExists(at: url) else {
            throw AuthManagerError.missingProfile(normalizedName)
        }
        let payload = try fileIO.readValidatedAuthFile(at: url)
        return try applyValidatedAuth(payload,
                                      sourceDescription: "profile '\(normalizedName)'",
                                      activeAccountID: payload.document.tokens.account_id)
    }

    public func applyAuthFile(path: URL) throws -> SwitchResult {
        let payload = try fileIO.readValidatedAuthFile(at: path)
        return try applyValidatedAuth(payload,
                                      sourceDescription: path.path,
                                      activeAccountID: payload.document.tokens.account_id)
    }

    public func currentProfileName() throws -> String? {
        try profileService.currentProfileName(currentAuthURL: paths.codexAuthFile)
    }

    public func activeProfileName() throws -> String? {
        try fileIO.ensureDirectories()
        guard let activeAccountID = fileIO.readActiveAccountID() else {
            return nil
        }
        guard let normalizedName = try profileService.profileName(forAccountID: activeAccountID) else {
            try fileIO.clearActiveAccountID()
            return nil
        }
        return normalizedName
    }

    public func syncActiveProfileWithCurrentAuth() throws -> Bool {
        try fileIO.ensureDirectories()

        guard let activeAccountID = fileIO.readActiveAccountID() else {
            return false
        }

        let current = try fileIO.readValidatedAuthFile(at: paths.codexAuthFile)
        guard current.document.tokens.account_id == activeAccountID else {
            return false
        }

        guard let activeName = try profileService.profileName(forAccountID: activeAccountID) else {
            try fileIO.clearActiveAccountID()
            return false
        }

        let profileURL = fileIO.profileURL(for: activeName)
        let existing = try fileIO.readValidatedAuthFile(at: profileURL)

        guard existing.document != current.document else {
            return false
        }

        try fileIO.writeSecureAtomically(data: current.rawData, to: profileURL)
        return true
    }

    public func currentAuthDocument() throws -> CodexAuthDocument {
        try fileIO.readValidatedAuthFile(at: paths.codexAuthFile).document
    }

    private func applyValidatedAuth(_ payload: ValidatedAuthFile,
                                    sourceDescription: String,
                                    activeAccountID: String?) throws -> SwitchResult {
        try fileIO.ensureDirectories()
        let lock = try FileLock(lockFile: paths.codexAuthLockFile)

        try fileIO.writeSecureAtomically(data: payload.rawData, to: paths.codexAuthFile)
        if let activeAccountID {
            try fileIO.writeActiveAccountID(activeAccountID)
        } else {
            try fileIO.clearActiveAccountID()
        }
        _ = lock
        let invalidation = sessionInvalidator.invalidateRunningCodexSessions()

        return SwitchResult(destination: paths.codexAuthFile,
                            backup: nil,
                            sourceDescription: sourceDescription,
                            invalidation: invalidation)
    }
}
