import Foundation

extension CredentialRecord {
    /// A stored credential's identity and dates, with its username only where
    /// an account is matched.
    init(_ descriptor: CredentialDescriptor, includesUsername: Bool) {
        self.init(
            id: descriptor.id,
            username: includesUsername ? descriptor.username : nil,
            updatedAt: descriptor.updatedAt.timeIntervalSince1970,
            lastUsedAt: descriptor.lastUsedAt?.timeIntervalSince1970)
    }
}
