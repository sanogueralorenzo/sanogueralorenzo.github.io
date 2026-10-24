protocol CredentialKeychainStoring: Sendable {
    func descriptorItems(in service: String) async throws -> [CredentialKeychainDescriptorItem]
    func items(in service: String) async throws -> [CredentialKeychainItem]
    func item(account: String, in service: String) async throws -> CredentialKeychainItem?
    func upsert(_ item: CredentialKeychainItem, in service: String) async throws
    func delete(account: String, in service: String) async throws
    func deleteAll(in service: String) async throws
}
