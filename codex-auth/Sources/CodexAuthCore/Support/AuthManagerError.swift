import Foundation

public enum AuthManagerError: LocalizedError {
    case invalidProfileName(String)
    case invalidAuthFile(URL)
    case missingProfile(String)
    case missingCurrentToken(URL)
    case duplicateProfileName(existingProfile: String)
    case duplicateProfileToken(existingProfile: String)
    case ioFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidProfileName(let name):
            return "Invalid profile name '\(name)'. Use at least one letter or number; names are normalized to lowercase-with-dashes."
        case .invalidAuthFile(let url):
            return "Invalid auth file at \(url.path). Expected Codex auth.json format."
        case .missingProfile(let name):
            return "Profile '\(name)' was not found."
        case .missingCurrentToken(let path):
            return "Cannot save profile because current Codex token is missing or invalid at \(path.path)."
        case .duplicateProfileName(let existingProfile):
            return "A profile with the same normalized name already exists: '\(existingProfile)'."
        case .duplicateProfileToken(let existingProfile):
            return "A profile with the same token payload already exists: '\(existingProfile)'."
        case .ioFailure(let message):
            return message
        }
    }
}
