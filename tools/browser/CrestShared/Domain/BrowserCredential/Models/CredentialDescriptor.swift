import Foundation

struct CredentialDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let spaceID: UUID
    let origin: CredentialOrigin
    var scope: BrowserCredentialScope
    var username: String
    var displayName: String?
    let createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var isSynchronizable: Bool

    init(
        id: UUID = UUID(),
        spaceID: UUID,
        origin: CredentialOrigin,
        scope: BrowserCredentialScope = .webForm,
        username: String,
        displayName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        isSynchronizable: Bool = false
    ) {
        self.id = id
        self.spaceID = spaceID
        self.origin = origin
        self.scope = scope
        self.username = username
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastUsedAt = lastUsedAt
        self.isSynchronizable = isSynchronizable
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case spaceID
        case origin
        case scope
        case username
        case displayName
        case createdAt
        case updatedAt
        case lastUsedAt
        case isSynchronizable
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIdentity(forKey: .id)
        spaceID = try container.decodeIdentity(forKey: .spaceID)
        origin = try container.decode(CredentialOrigin.self, forKey: .origin)
        scope =
            try container.decodeIfPresent(BrowserCredentialScope.self, forKey: .scope)
            ?? .webForm
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        isSynchronizable = try container.decode(Bool.self, forKey: .isSynchronizable)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Descriptors keep the identity spelling every earlier build wrote.
        try container.encodeStoredIdentity(id, forKey: .id)
        // Synchronizable descriptors reach older builds on other devices,
        // which read only the stored spelling, so it stays for good.
        try container.encodeStoredIdentity(spaceID, forKey: .spaceID)
        try container.encode(origin, forKey: .origin)
        try container.encode(scope, forKey: .scope)
        try container.encode(username, forKey: .username)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encode(isSynchronizable, forKey: .isSynchronizable)
    }
}
