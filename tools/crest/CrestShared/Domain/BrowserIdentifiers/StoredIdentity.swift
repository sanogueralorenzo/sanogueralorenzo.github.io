import Foundation

/// The spelling Crest stores an identity in: `{"rawValue": UUID}`, as the ID
/// wrappers wrote it before they became plain `UUID`s. Reading also accepts a
/// bare UUID.
///
/// Keychain credential descriptors keep writing this spelling for good, since
/// older builds on the person's other devices read them. Local defaults and
/// scene values keep it until a release drops rollback support.
private struct StoredIdentity: Codable {
    // MARK: - Types

    private enum CodingKeys: String, CodingKey {
        case rawValue
    }

    // MARK: - Variables

    let value: UUID

    // MARK: - Initializers

    init(_ value: UUID) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        if let wrapped = try? decoder.container(keyedBy: CodingKeys.self), wrapped.contains(.rawValue) {
            value = try wrapped.decode(UUID.self, forKey: .rawValue)
        } else {
            value = try decoder.singleValueContainer().decode(UUID.self)
        }
    }

    // MARK: - Actions - Coding

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .rawValue)
    }
}

// MARK: - Reading

extension Decoder {
    /// This value as an identity, stored bare or as `{"rawValue": UUID}`.
    func decodeIdentity() throws -> UUID {
        try StoredIdentity(from: self).value
    }
}

extension KeyedDecodingContainer {
    /// The identity under `key`, stored bare or as `{"rawValue": UUID}`.
    func decodeIdentity(forKey key: Key) throws -> UUID {
        try decode(StoredIdentity.self, forKey: key).value
    }

    func decodeIdentityIfPresent(forKey key: Key) throws -> UUID? {
        try decodeIfPresent(StoredIdentity.self, forKey: key)?.value
    }

}

// MARK: - Writing

extension Encoder {
    /// Writes `id` as this value in the stored spelling, `{"rawValue": UUID}`.
    func encodeStoredIdentity(_ id: UUID) throws {
        try StoredIdentity(id).encode(to: self)
    }
}

extension KeyedEncodingContainer {
    /// Writes `id` under `key` in the stored spelling, `{"rawValue": UUID}`.
    mutating func encodeStoredIdentity(_ id: UUID, forKey key: Key) throws {
        try encode(StoredIdentity(id), forKey: key)
    }

    mutating func encodeStoredIdentityIfPresent(_ id: UUID?, forKey key: Key) throws {
        try encodeIfPresent(id.map(StoredIdentity.init), forKey: key)
    }

}
