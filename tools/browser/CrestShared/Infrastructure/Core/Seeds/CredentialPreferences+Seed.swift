import Foundation

extension CredentialPreferences {
    // MARK: - Variables

    /// A seeded Space offers to save passwords and sync them with iCloud,
    /// never to the system's passwords, unless told otherwise.
    static let seeded = CredentialPreferences(
        isEnabled: true, syncsCrestPasswordsWithICloud: true, alsoOffersSaveToSystemPasswords: false)
}
