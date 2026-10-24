import Foundation

struct CredentialKeychainDescriptorItem: Equatable, Sendable {
    let account: String
    let metadata: Data
    let isSynchronizable: Bool
}

struct CredentialKeychainItem: Equatable, Sendable {
    let account: String
    let metadata: Data
    let secret: Data
    let isSynchronizable: Bool
}
