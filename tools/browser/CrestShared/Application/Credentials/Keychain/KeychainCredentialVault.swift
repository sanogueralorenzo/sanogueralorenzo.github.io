import Foundation

actor KeychainCredentialVault: CredentialVault {
    private let store: any CredentialKeychainStoring
    private let servicePrefix: String
    private let codec = CredentialKeychainCodec()

    init(
        store: any CredentialKeychainStoring,
        servicePrefix: String = CredentialKeychainNamespace.productionPrefix
    ) {
        self.store = store
        self.servicePrefix = servicePrefix
    }

    func descriptors(in spaceID: UUID) async throws -> [CredentialDescriptor] {
        let items = try await store.descriptorItems(in: service(for: spaceID))
        return
            try items
            .map { try codec.descriptor(from: $0, expectedSpaceID: spaceID) }
            .sorted(by: Self.descriptorOrder)
    }

    func descriptors(
        matching origin: CredentialOrigin,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        let items = try await store.descriptorItems(in: service(for: spaceID))
        return
            try items
            .map { try codec.descriptor(from: $0, expectedSpaceID: spaceID) }
            .filter { $0.origin == origin && $0.scope == .webForm }
            .sorted(by: Self.descriptorOrder)
    }

    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        let items = try await store.descriptorItems(in: service(for: spaceID))
        return
            try items
            .map { try codec.descriptor(from: $0, expectedSpaceID: spaceID) }
            .filter {
                $0.origin == protectionSpace.origin
                    && $0.scope == protectionSpace.credentialScope
            }
            .sorted(by: Self.descriptorOrder)
    }

    func credential(
        id: UUID,
        in spaceID: UUID
    ) async throws -> BrowserCredential? {
        let account = id.uuidString.lowercased()
        guard
            let item = try await store.item(
                account: account,
                in: service(for: spaceID)
            )
        else {
            return nil
        }
        return try codec.credential(
            from: item,
            expectedID: id,
            expectedSpaceID: spaceID
        )
    }

    func save(_ credential: BrowserCredential, in spaceID: UUID) async throws {
        let item = try codec.item(
            for: credential,
            expectedSpaceID: spaceID
        )
        try await store.upsert(item, in: service(for: spaceID))
    }

    func replaceAll(
        _ credentials: [BrowserCredential],
        in spaceID: UUID
    ) async throws {
        let service = service(for: spaceID)
        let replacementItems = try credentials.map {
            try codec.item(for: $0, expectedSpaceID: spaceID)
        }
        guard Set(replacementItems.map(\.account)).count == replacementItems.count else {
            throw CredentialVaultError.malformedStoredCredential
        }
        let originalItems = try await store.items(in: service)

        do {
            try await store.deleteAll(in: service)
            for item in replacementItems {
                try await store.upsert(item, in: service)
            }
        } catch {
            do {
                try await store.deleteAll(in: service)
                for originalItem in originalItems {
                    try await store.upsert(originalItem, in: service)
                }
            } catch {
                throw CredentialVaultError.atomicReplacementRestoreFailed
            }
            throw error
        }
    }

    func setSynchronizable(
        _ isSynchronizable: Bool,
        in spaceID: UUID
    ) async throws {
        let service = service(for: spaceID)
        let originalItems = try await store.items(in: service)
        var migratedOriginalItems: [CredentialKeychainItem] = []

        do {
            for item in originalItems where item.isSynchronizable != isSynchronizable {
                let migratedItem = try codec.migratedItem(
                    from: item,
                    isSynchronizable: isSynchronizable,
                    expectedSpaceID: spaceID
                )
                try await store.upsert(migratedItem, in: service)
                migratedOriginalItems.append(item)
            }
        } catch {
            for originalItem in migratedOriginalItems.reversed() {
                try? await store.upsert(originalItem, in: service)
            }
            throw error
        }
    }

    func delete(id: UUID, in spaceID: UUID) async throws {
        try await store.delete(
            account: id.uuidString.lowercased(),
            in: service(for: spaceID)
        )
    }

    func deleteAll(in spaceID: UUID) async throws {
        try await store.deleteAll(in: service(for: spaceID))
    }

    private func service(for spaceID: UUID) -> String {
        CredentialKeychainNamespace.service(for: spaceID, prefix: servicePrefix)
    }

    private static func descriptorOrder(
        _ lhs: CredentialDescriptor,
        _ rhs: CredentialDescriptor
    ) -> Bool {
        let usernameOrder = lhs.username.localizedCaseInsensitiveCompare(rhs.username)
        if usernameOrder != .orderedSame {
            return usernameOrder == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
