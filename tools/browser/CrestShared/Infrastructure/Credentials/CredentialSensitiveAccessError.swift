import Foundation

enum BrowserCredentialSensitiveAccessError: Error, Equatable, Sendable {
    case authenticationDenied
    case missingCredential
    case malformedCredentialInventory
}
