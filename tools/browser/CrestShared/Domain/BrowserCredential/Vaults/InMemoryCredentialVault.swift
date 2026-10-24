import Foundation

actor InMemoryCredentialVault: CredentialVault {
    private var credentialsBySpace: [UUID: [UUID: BrowserCredential]] = [:]

    func descriptors(in spaceID: UUID) -> [CredentialDescriptor] {
        sortedDescriptors(
            credentialsBySpace[spaceID, default: [:]].values.map(\.descriptor)
        )
    }

    func descriptors(
        matching origin: CredentialOrigin,
        in spaceID: UUID
    ) -> [CredentialDescriptor] {
        sortedDescriptors(
            credentialsBySpace[spaceID, default: [:]].values
                .filter {
                    $0.descriptor.origin == origin
                        && $0.descriptor.scope == .webForm
                }
                .map(\.descriptor)
        )
    }

    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID
    ) -> [CredentialDescriptor] {
        sortedDescriptors(
            credentialsBySpace[spaceID, default: [:]].values
                .filter {
                    $0.descriptor.origin == protectionSpace.origin
                        && $0.descriptor.scope == protectionSpace.credentialScope
                }
                .map(\.descriptor)
        )
    }

    func credential(id: UUID, in spaceID: UUID) -> BrowserCredential? {
        credentialsBySpace[spaceID]?[id]
    }

    func save(_ credential: BrowserCredential, in spaceID: UUID) throws {
        guard credential.descriptor.spaceID == spaceID else {
            throw CredentialVaultError.spaceMismatch(
                expected: spaceID,
                actual: credential.descriptor.spaceID
            )
        }
        credentialsBySpace[spaceID, default: [:]][credential.descriptor.id] = credential
    }

    func replaceAll(_ credentials: [BrowserCredential], in spaceID: UUID) throws {
        for credential in credentials where credential.descriptor.spaceID != spaceID {
            throw CredentialVaultError.spaceMismatch(
                expected: spaceID,
                actual: credential.descriptor.spaceID
            )
        }
        credentialsBySpace[spaceID] = Dictionary(
            uniqueKeysWithValues: credentials.map { ($0.descriptor.id, $0) }
        )
    }

    func setSynchronizable(_ isSynchronizable: Bool, in spaceID: UUID) {
        guard var credentials = credentialsBySpace[spaceID] else { return }
        for id in credentials.keys {
            credentials[id]?.descriptor.isSynchronizable = isSynchronizable
        }
        credentialsBySpace[spaceID] = credentials
    }

    func delete(id: UUID, in spaceID: UUID) {
        credentialsBySpace[spaceID]?[id] = nil
        if credentialsBySpace[spaceID]?.isEmpty == true {
            credentialsBySpace[spaceID] = nil
        }
    }

    func deleteAll(in spaceID: UUID) {
        credentialsBySpace[spaceID] = nil
    }

    private func sortedDescriptors(_ descriptors: [CredentialDescriptor]) -> [CredentialDescriptor] {
        descriptors.sorted {
            let usernameOrder = $0.username.localizedCaseInsensitiveCompare($1.username)
            if usernameOrder != .orderedSame {
                return usernameOrder == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
