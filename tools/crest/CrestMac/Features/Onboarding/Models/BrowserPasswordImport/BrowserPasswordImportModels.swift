import Foundation

struct BrowserEncryptedPasswordRecord {
    let origin: CredentialOrigin
    let username: String
    let encryptedPassword: Data
}

struct BrowserImportedPassword:
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let sourceApplication: ImportSource
    let sourceProfileID: String
    let sourceProfileName: String
    let origin: CredentialOrigin
    let username: String
    let password: String

    var description: String {
        "BrowserImportedPassword(profile: \(sourceProfileID), origin: \(origin), username: <redacted>, password: <redacted>)"
    }

    var debugDescription: String { description }
}

struct BrowserPasswordImportCandidate: Sendable {
    let sourceApplication: ImportSource
    let sourceProfileID: String
    let sourceProfileName: String
    let origin: CredentialOrigin
}

enum BrowserPasswordImportError: LocalizedError, Equatable, Sendable {
    case unsupportedBrowser
    case safeStorageUnavailable
    case unreadableDatabase
    case unsupportedEncryption

    var errorDescription: String? {
        switch self {
        case .unsupportedBrowser:
            "Crest cannot import passwords from this browser yet."
        case .safeStorageUnavailable:
            "Crest could not unlock this browser’s passwords. Allow Keychain access, or turn password import off to continue."
        case .unreadableDatabase:
            "Crest could not read this browser’s password database. Close the source browser and try again."
        case .unsupportedEncryption:
            "This browser uses a password format Crest cannot import safely."
        }
    }
}

struct BrowserPasswordImportResult: Equatable, Sendable {
    let importedCount: Int
    let skippedCount: Int

    static let empty = BrowserPasswordImportResult(
        importedCount: 0,
        skippedCount: 0
    )
}
