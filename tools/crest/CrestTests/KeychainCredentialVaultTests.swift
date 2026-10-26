import Foundation
import XCTest

@testable import Crest

@MainActor
final class KeychainCredentialVaultTests: XCTestCase {
    func testAtomicReplacementRestoresTheOriginalInventoryWhenAWriteFails() async throws {
        let spaceID = UUID()
        let firstDescriptor = descriptor(
            id: UUID(),
            spaceID: spaceID,
            username: "first"
        )
        let secondDescriptor = descriptor(
            id: UUID(),
            spaceID: spaceID,
            username: "second"
        )
        let first = try keychainItem(
            descriptor: firstDescriptor,
            password: "first-original"
        )
        let second = try keychainItem(
            descriptor: secondDescriptor,
            password: "second-original"
        )
        let store = FailingMigrationCredentialKeychainStore(
            items: [first, second],
            failingAccount: second.account
        )
        let vault = KeychainCredentialVault(
            store: store,
            servicePrefix: "test.crest"
        )
        var synchronizedFirst = firstDescriptor
        synchronizedFirst.isSynchronizable = true
        var synchronizedSecond = secondDescriptor
        synchronizedSecond.isSynchronizable = true

        do {
            try await vault.replaceAll(
                [
                    BrowserCredential(
                        descriptor: synchronizedFirst,
                        password: "first-replacement"
                    ),
                    BrowserCredential(
                        descriptor: synchronizedSecond,
                        password: "second-replacement"
                    ),
                ],
                in: spaceID
            )
            XCTFail("Expected the replacement write to fail")
        } catch {
            XCTAssertEqual(error as? TestCredentialKeychainError, .injectedFailure)
        }

        let restoredItems = await store.storedItems
        XCTAssertEqual(restoredItems, [first, second])
    }

    /// Synchronizable descriptors reach builds on other devices that read a
    /// Space only as `{"rawValue": UUID}`. What this build writes decodes
    /// with that older shape, and what an older build wrote reads here.
    func testDescriptorsKeepTheSpaceSpellingOlderBuildsRead() async throws {
        let spaceID = UUID()
        var written = descriptor(id: UUID(), spaceID: spaceID, username: "person")
        written.isSynchronizable = true
        let item = try CredentialKeychainCodec().item(
            for: BrowserCredential(descriptor: written, password: "secret"), expectedSpaceID: spaceID)

        let older = try JSONDecoder().decode(PreS62CredentialDescriptor.self, from: item.metadata)
        XCTAssertEqual(older.spaceID.rawValue, spaceID)
        XCTAssertEqual(older.id.rawValue, written.id)
        XCTAssertEqual(older.username, written.username)
        XCTAssertTrue(older.isSynchronizable)

        let olderItem = CredentialKeychainItem(
            account: item.account, metadata: try JSONEncoder().encode(older), secret: item.secret,
            isSynchronizable: true)
        let vault = KeychainCredentialVault(
            store: FailingMigrationCredentialKeychainStore(items: [olderItem]), servicePrefix: "test.crest")
        let read = try await vault.descriptors(in: spaceID)
        XCTAssertEqual(read, [written])
    }

    /// A saved IPv6 origin reads back, so the Space's passwords stay readable.
    func testDescriptorsReadAnIPv6Origin() async throws {
        let spaceID = UUID()
        let origin = try XCTUnwrap(CredentialOrigin(url: URL(string: "http://[2001:DB8::1]:8001/login")!))
        let written = descriptor(id: UUID(), spaceID: spaceID, username: "person", origin: origin)
        let item = try CredentialKeychainCodec().item(
            for: BrowserCredential(descriptor: written, password: "secret"), expectedSpaceID: spaceID)
        let vault = KeychainCredentialVault(
            store: FailingMigrationCredentialKeychainStore(items: [item]), servicePrefix: "test.crest")

        let read = try await vault.descriptors(in: spaceID)
        XCTAssertEqual(read, [written])
        XCTAssertEqual(read.first?.origin.host, "2001:db8::1")
    }

    /// An origin that would not read back is refused when it is written, so it
    /// never reaches the Keychain and blocks reading the Space.
    func testItemsRefuseAnOriginThatWouldNotReadBack() {
        let spaceID = UUID()
        let written = descriptor(
            id: UUID(), spaceID: spaceID, username: "person",
            origin: CredentialOrigin(scheme: "https", host: "a b", port: 443))

        XCTAssertThrowsError(
            try CredentialKeychainCodec().item(
                for: BrowserCredential(descriptor: written, password: "secret"), expectedSpaceID: spaceID)
        ) { error in
            XCTAssertEqual(error as? CredentialVaultError, .malformedStoredCredential)
        }
    }

    /// An item that no longer reads back is left out of the Space's listings
    /// instead of failing them, keeps its place through a replacement and an
    /// iCloud change, and goes only when asked.
    func testAnUnreadableItemIsLeftOutKeptAndRemovedOnRequest() async throws {
        let spaceID = UUID()
        let readable = descriptor(id: UUID(), spaceID: spaceID, username: "person")
        let readableItem = try keychainItem(descriptor: readable, password: "secret")
        let unreadable = descriptor(
            id: UUID(), spaceID: spaceID, username: "zone",
            origin: CredentialOrigin(scheme: "https", host: "fe80::1%en0", port: 443))
        let unreadableItem = try keychainItem(descriptor: unreadable, password: "zone-secret")
        let store = FailingMigrationCredentialKeychainStore(items: [readableItem, unreadableItem])
        let vault = KeychainCredentialVault(store: store, servicePrefix: "test.crest")

        let listed = try await vault.descriptors(in: spaceID)
        XCTAssertEqual(listed, [readable])
        let unreadableCount = try await vault.unreadableCredentialCount(in: spaceID)
        XCTAssertEqual(unreadableCount, 1)

        try await vault.replaceAll([BrowserCredential(descriptor: readable, password: "changed")], in: spaceID)
        try await vault.setSynchronizable(true, in: spaceID)
        let keptItems = await store.storedItems
        XCTAssertEqual(keptItems.map(\.account), [readableItem.account, unreadableItem.account])
        XCTAssertEqual(keptItems.map(\.isSynchronizable), [true, false])

        try await vault.deleteUnreadableCredentials(in: spaceID)
        let remainingItems = await store.storedItems
        XCTAssertEqual(remainingItems.map(\.account), [readableItem.account])
        XCTAssertEqual(String(data: remainingItems[0].secret, encoding: .utf8), "changed")
    }

    private func descriptor(
        id: UUID,
        spaceID: UUID,
        username: String,
        origin: CredentialOrigin = CredentialOrigin(
            securityProtocol: "https",
            host: "example.com",
            port: 443
        )!
    ) -> CredentialDescriptor {
        CredentialDescriptor(
            id: id,
            spaceID: spaceID,
            origin: origin,
            username: username,
            createdAt: Date(timeIntervalSince1970: 1_000),
            isSynchronizable: false
        )
    }

    private func keychainItem(
        descriptor: CredentialDescriptor,
        password: String
    ) throws -> CredentialKeychainItem {
        CredentialKeychainItem(
            account: descriptor.id.uuidString.lowercased(),
            metadata: try JSONEncoder().encode(descriptor),
            secret: Data(password.utf8),
            isSynchronizable: descriptor.isSynchronizable
        )
    }
}

private enum TestCredentialKeychainError: Error, Equatable {
    case injectedFailure
}

/// The credential descriptor as builds before S6.2 coded it, with the Space in
/// its ID wrapper.
private struct PreS62CredentialDescriptor: Codable {
    struct WrappedIdentity: Codable {
        let rawValue: UUID
    }

    let id: WrappedIdentity
    let spaceID: WrappedIdentity
    let origin: CredentialOrigin
    let scope: BrowserCredentialScope
    let username: String
    let displayName: String?
    let createdAt: Date
    let updatedAt: Date
    let lastUsedAt: Date?
    let isSynchronizable: Bool
}

private actor FailingMigrationCredentialKeychainStore: CredentialKeychainStoring {
    private var itemsByAccount: [String: CredentialKeychainItem]
    private let accountOrder: [String]
    private let failingAccount: String?
    private var hasInjectedFailure = false
    private(set) var writes: [CredentialKeychainItem] = []

    init(
        items: [CredentialKeychainItem],
        failingAccount: String? = nil
    ) {
        itemsByAccount = Dictionary(
            uniqueKeysWithValues: items.map { ($0.account, $0) }
        )
        accountOrder = items.map(\.account)
        self.failingAccount = failingAccount
    }

    var storedItems: [CredentialKeychainItem] {
        accountOrder.compactMap { itemsByAccount[$0] }
    }

    func descriptorItems(in _: String) -> [CredentialKeychainDescriptorItem] {
        storedItems.map {
            CredentialKeychainDescriptorItem(
                account: $0.account,
                metadata: $0.metadata,
                isSynchronizable: $0.isSynchronizable
            )
        }
    }

    func items(in _: String) -> [CredentialKeychainItem] { storedItems }

    func item(
        account: String,
        in _: String
    ) -> CredentialKeychainItem? {
        itemsByAccount[account]
    }

    func upsert(_ item: CredentialKeychainItem, in _: String) throws {
        writes.append(item)
        if item.account == failingAccount,
            item.isSynchronizable,
            !hasInjectedFailure
        {
            hasInjectedFailure = true
            throw TestCredentialKeychainError.injectedFailure
        }
        itemsByAccount[item.account] = item
    }

    func delete(account: String, in _: String) {
        itemsByAccount[account] = nil
    }

    func deleteAll(in _: String) {
        itemsByAccount.removeAll()
    }
}
