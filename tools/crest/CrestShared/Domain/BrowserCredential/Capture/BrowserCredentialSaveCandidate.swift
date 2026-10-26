import Foundation

/// A password stays only in process memory until the person accepts or dismisses
/// the native save/update prompt. This value is deliberately non-Codable and redacted.
struct BrowserCredentialSaveCandidate: Identifiable, Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    let id: UUID
    let origin: CredentialOrigin
    let topLevelOrigin: CredentialOrigin
    let username: String
    let password: String
    let passwordKind: CredentialPasswordKind
    let isCrossOriginFrame: Bool
    let submittedAt: Date

    var description: String {
        "BrowserCredentialSaveCandidate(id: \(id), origin: \(origin), username: \(username), password: <redacted>)"
    }

    var debugDescription: String { description }
}
