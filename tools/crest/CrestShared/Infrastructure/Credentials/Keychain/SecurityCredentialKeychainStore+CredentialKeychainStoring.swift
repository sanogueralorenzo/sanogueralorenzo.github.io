import Foundation
import Security

extension SecurityCredentialKeychainStore: CredentialKeychainStoring {
    func descriptorItems(
        in service: String
    ) async throws -> [CredentialKeychainDescriptorItem] {
        try await Task.detached(priority: .userInitiated) { [self] in
            var query = baseQuery(service: service)
            query[kSecMatchLimit] = kSecMatchLimitAll
            query[kSecReturnAttributes] = true

            let result = try copyMatching(query)
            guard let result else { return [] }

            if let dictionaries = result as? [NSDictionary] {
                return try dictionaries.map(decodeDescriptorItem)
            }
            if let dictionary = result as? NSDictionary {
                return [try decodeDescriptorItem(dictionary)]
            }
            throw SecurityCredentialKeychainError.unexpectedResult
        }.value
    }

    func items(in service: String) async throws -> [CredentialKeychainItem] {
        var query = baseQuery(service: service)
        query[kSecMatchLimit] = kSecMatchLimitAll
        query[kSecReturnAttributes] = true
        query[kSecReturnData] = true

        let result = try copyMatching(query)
        guard let result else { return [] }

        if let dictionaries = result as? [NSDictionary] {
            return try dictionaries.map(decodeItem)
        }
        if let dictionary = result as? NSDictionary {
            return [try decodeItem(dictionary)]
        }
        throw SecurityCredentialKeychainError.unexpectedResult
    }

    func item(
        account: String,
        in service: String
    ) async throws -> CredentialKeychainItem? {
        var query = baseQuery(service: service, account: account)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnAttributes] = true
        query[kSecReturnData] = true

        guard let result = try copyMatching(query) else { return nil }
        guard let dictionary = result as? NSDictionary else {
            throw SecurityCredentialKeychainError.unexpectedResult
        }
        return try decodeItem(dictionary)
    }

    func upsert(
        _ item: CredentialKeychainItem,
        in service: String
    ) async throws {
        if let existing = try await self.item(account: item.account, in: service),
            existing.isSynchronizable != item.isSynchronizable
        {
            try deleteItem(account: item.account, in: service)
            do {
                try add(item, in: service)
            } catch {
                try? add(existing, in: service)
                throw error
            }
            return
        }

        var query = baseQuery(service: service, account: item.account)
        query[kSecAttrSynchronizable] = item.isSynchronizable
        let attributes: [CFString: Any] = [
            kSecAttrGeneric: item.metadata,
            kSecValueData: item.secret,
            kSecAttrLabel: Self.itemLabel,
        ]
        let status = client.update(query, attributes: attributes)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            try add(item, in: service)
        default:
            throw SecurityCredentialKeychainError.status(status)
        }
    }

    func delete(account: String, in service: String) async throws {
        try deleteItem(account: account, in: service)
    }

    func deleteAll(in service: String) async throws {
        let status = client.delete(baseQuery(service: service))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityCredentialKeychainError.status(status)
        }
    }

    private func add(
        _ item: CredentialKeychainItem,
        in service: String
    ) throws {
        var attributes = baseQuery(service: service, account: item.account)
        attributes[kSecAttrGeneric] = item.metadata
        attributes[kSecValueData] = item.secret
        attributes[kSecAttrLabel] = Self.itemLabel
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        attributes[kSecAttrSynchronizable] = item.isSynchronizable

        let status = client.add(attributes)
        guard status == errSecSuccess else {
            throw SecurityCredentialKeychainError.status(status)
        }
    }

    private func deleteItem(account: String, in service: String) throws {
        let status = client.delete(
            baseQuery(service: service, account: account)
        )
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityCredentialKeychainError.status(status)
        }
    }

    private func baseQuery(
        service: String,
        account: String? = nil
    ) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrSynchronizable: kSecAttrSynchronizableAny,
            kSecUseDataProtectionKeychain: true,
        ]
        if let account {
            query[kSecAttrAccount] = account
        }
        return query
    }

    private func copyMatching(
        _ query: [CFString: Any]
    ) throws -> CFTypeRef? {
        let response = client.copyMatching(query)
        switch response.status {
        case errSecSuccess:
            return response.result
        case errSecItemNotFound:
            return nil
        default:
            throw SecurityCredentialKeychainError.status(response.status)
        }
    }

    private func decodeItem(
        _ dictionary: NSDictionary
    ) throws -> CredentialKeychainItem {
        guard let account = dictionary[kSecAttrAccount] as? String,
            let metadata = dictionary[kSecAttrGeneric] as? Data,
            let secret = dictionary[kSecValueData] as? Data
        else {
            throw SecurityCredentialKeychainError.unexpectedResult
        }

        let synchronizableValue = dictionary[kSecAttrSynchronizable]
        let isSynchronizable =
            (synchronizableValue as? Bool)
            ?? (synchronizableValue as? NSNumber)?.boolValue
            ?? false
        return CredentialKeychainItem(
            account: account,
            metadata: metadata,
            secret: secret,
            isSynchronizable: isSynchronizable
        )
    }

    private func decodeDescriptorItem(
        _ dictionary: NSDictionary
    ) throws -> CredentialKeychainDescriptorItem {
        guard let account = dictionary[kSecAttrAccount] as? String,
            let metadata = dictionary[kSecAttrGeneric] as? Data
        else {
            throw SecurityCredentialKeychainError.unexpectedResult
        }

        let synchronizableValue = dictionary[kSecAttrSynchronizable]
        let isSynchronizable =
            (synchronizableValue as? Bool)
            ?? (synchronizableValue as? NSNumber)?.boolValue
            ?? false
        return CredentialKeychainDescriptorItem(
            account: account,
            metadata: metadata,
            isSynchronizable: isSynchronizable
        )
    }
}
