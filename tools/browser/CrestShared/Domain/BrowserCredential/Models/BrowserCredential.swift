import Foundation

/// A credential deliberately does not conform to `Codable`: passwords must never
/// enter the browser session JSON or a CloudKit record by accident.
struct BrowserCredential: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    var descriptor: CredentialDescriptor
    var password: String

    var description: String {
        "BrowserCredential(descriptor: \(descriptor), password: <redacted>)"
    }

    var debugDescription: String { description }
}
