import Foundation

actor PrivateBrowsingCredentialVault: CredentialVault {
    func descriptors(in spaceID: UUID) async throws -> [CredentialDescriptor] {
        []
    }

    func descriptors(
        matching origin: CredentialOrigin,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        []
    }

    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        []
    }

    func credential(
        id: UUID,
        in spaceID: UUID
    ) async throws -> BrowserCredential? {
        nil
    }

    func save(_ credential: BrowserCredential, in spaceID: UUID) async throws {
        throw CredentialVaultError.unavailableInPrivateBrowsing
    }

    func replaceAll(_ credentials: [BrowserCredential], in spaceID: UUID) async throws {
        throw CredentialVaultError.unavailableInPrivateBrowsing
    }

    func setSynchronizable(_ isSynchronizable: Bool, in spaceID: UUID) async throws {
        throw CredentialVaultError.unavailableInPrivateBrowsing
    }

    func delete(id: UUID, in spaceID: UUID) async throws {}

    func deleteAll(in spaceID: UUID) async throws {}
}
