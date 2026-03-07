import Foundation

final class ProfileService {
    private let fileIO: ProfileFileIO

    init(fileIO: ProfileFileIO) {
        self.fileIO = fileIO
    }

    func normalizedProfileName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthManagerError.invalidProfileName(name)
        }

        var normalized = ""
        var previousWasSeparator = false

        for scalar in trimmed.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                normalized.append(contentsOf: String(scalar).lowercased())
                previousWasSeparator = false
            } else if !normalized.isEmpty && !previousWasSeparator {
                normalized.append("-")
                previousWasSeparator = true
            }
        }

        if normalized.hasSuffix("-") {
            normalized.removeLast()
        }

        guard !normalized.isEmpty else {
            throw AuthManagerError.invalidProfileName(name)
        }

        return normalized
    }

    func ensureUniqueProfile(normalizedName: String, payload: ValidatedAuthFile) throws {
        for existingName in try fileIO.listProfiles() where existingName != normalizedName {
            let existing = try fileIO.readValidatedAuthFile(at: fileIO.profileURL(for: existingName))
            if existing.document == payload.document {
                throw AuthManagerError.duplicateProfileToken(existingProfile: existingName)
            }
        }
    }

    func listProfileNames() throws -> [String] {
        try fileIO.listProfiles()
    }

    func currentProfileName(currentAuthURL: URL) throws -> String? {
        let current = try fileIO.readValidatedAuthFile(at: currentAuthURL)
        for normalizedName in try fileIO.listProfiles() {
            let profile = try fileIO.readValidatedAuthFile(at: fileIO.profileURL(for: normalizedName))
            if profile.document == current.document {
                return normalizedName
            }
        }
        return nil
    }
}
