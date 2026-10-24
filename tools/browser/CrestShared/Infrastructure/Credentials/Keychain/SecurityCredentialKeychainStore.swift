// MARK: - Types

enum SecurityCredentialKeychainError: Error, Equatable, Sendable {
    case unexpectedResult
    case status(Int32)
}

struct SecurityCredentialKeychainStore: Sendable {
    static let itemLabel = "Crest Password"

    let client: any SecurityCredentialKeychainClient

    init(
        client: any SecurityCredentialKeychainClient = SystemSecurityCredentialKeychainClient()
    ) {
        self.client = client
    }
}
