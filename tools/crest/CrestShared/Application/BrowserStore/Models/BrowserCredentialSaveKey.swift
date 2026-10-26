import Foundation

struct BrowserCredentialSaveKey: Hashable {
    let spaceID: UUID
    let origin: CredentialOrigin
    let normalizedUsername: String

    init(
        candidate: BrowserCredentialSaveCandidate,
        spaceID: UUID
    ) {
        self.spaceID = spaceID
        origin = candidate.origin
        normalizedUsername = candidate.username.lowercased()
    }
}
