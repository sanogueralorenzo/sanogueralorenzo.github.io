import Foundation

enum CredentialVaultError: Error, Equatable, Sendable {
    case invalidOrigin
    case insecureOrigin
    case missingSpace
    case unavailableInPrivateBrowsing
    case credentialManagerDisabled
    case staleSaveCandidate
    case spaceMismatch(expected: UUID, actual: UUID)
    case malformedStoredCredential
    case atomicReplacementRestoreFailed
    case preferenceUpdateFailed
    /// The portable core could not answer a save decision. Nothing is saved.
    case saveDecisionUnavailable
}
