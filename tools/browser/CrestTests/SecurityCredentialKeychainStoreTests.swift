import Foundation
import Security
import XCTest

@testable import Crest

@MainActor
final class SecurityCredentialKeychainStoreTests: XCTestCase {
    func testDescriptorInventoryUsesMetadataOnlyDataProtectionQuery() async throws {
        let metadata = Data("metadata".utf8)
        let client = RecordingSecurityCredentialKeychainClient(
            copyResponses: [
                .init(
                    status: errSecSuccess,
                    result: keychainDictionary(
                        account: "credential-account",
                        metadata: metadata,
                        isSynchronizable: true
                    ) as CFDictionary
                )
            ]
        )
        let store = SecurityCredentialKeychainStore(client: client)

        let items = try await store.descriptorItems(in: "test.service")

        XCTAssertEqual(
            items,
            [
                CredentialKeychainDescriptorItem(
                    account: "credential-account",
                    metadata: metadata,
                    isSynchronizable: true
                )
            ]
        )
        let query = try XCTUnwrap(client.copyQueries.first)
        assertBaseQuery(query, service: "test.service")
        assertCFValue(query[kSecMatchLimit], equals: kSecMatchLimitAll)
        XCTAssertEqual(query[kSecReturnAttributes] as? Bool, true)
        XCTAssertNil(query[kSecReturnData])
        XCTAssertNil(query[kSecAttrAccessGroup])
    }

    func testItemLookupScopesAccountAndRequestsSecretData() async throws {
        let metadata = Data("metadata".utf8)
        let secret = Data("secret".utf8)
        let client = RecordingSecurityCredentialKeychainClient(
            copyResponses: [
                .init(
                    status: errSecSuccess,
                    result: keychainDictionary(
                        account: "credential-account",
                        metadata: metadata,
                        secret: secret,
                        isSynchronizable: false
                    ) as CFDictionary
                )
            ]
        )
        let store = SecurityCredentialKeychainStore(client: client)

        let item = try await store.item(
            account: "credential-account",
            in: "test.service"
        )

        XCTAssertEqual(
            item,
            CredentialKeychainItem(
                account: "credential-account",
                metadata: metadata,
                secret: secret,
                isSynchronizable: false
            )
        )
        let query = try XCTUnwrap(client.copyQueries.first)
        assertBaseQuery(query, service: "test.service")
        XCTAssertEqual(query[kSecAttrAccount] as? String, "credential-account")
        assertCFValue(query[kSecMatchLimit], equals: kSecMatchLimitOne)
        XCTAssertEqual(query[kSecReturnAttributes] as? Bool, true)
        XCTAssertEqual(query[kSecReturnData] as? Bool, true)
        XCTAssertNil(query[kSecAttrAccessGroup])
    }

    func testUpsertUpdatesAnExistingSyncClassWithoutChangingAccessibility() async throws {
        let item = credentialItem(isSynchronizable: true)
        let client = RecordingSecurityCredentialKeychainClient(
            copyResponses: [
                .init(
                    status: errSecSuccess,
                    result: keychainDictionary(for: item) as CFDictionary
                )
            ],
            updateStatuses: [errSecSuccess]
        )
        let store = SecurityCredentialKeychainStore(client: client)

        try await store.upsert(item, in: "test.service")

        let update = try XCTUnwrap(client.updates.first)
        assertBaseQuery(
            update.query,
            service: "test.service",
            synchronizable: true
        )
        XCTAssertEqual(update.query[kSecAttrAccount] as? String, item.account)
        XCTAssertEqual(update.attributes[kSecAttrGeneric] as? Data, item.metadata)
        XCTAssertEqual(update.attributes[kSecValueData] as? Data, item.secret)
        XCTAssertEqual(
            update.attributes[kSecAttrLabel] as? String,
            SecurityCredentialKeychainStore.itemLabel
        )
        XCTAssertNil(update.attributes[kSecAttrAccessible])
        XCTAssertNil(update.attributes[kSecAttrAccessGroup])
        XCTAssertTrue(client.adds.isEmpty)
        XCTAssertTrue(client.deletes.isEmpty)
    }

    func testMissingUpsertAddsWhenUnlockedDataProtectionCredential() async throws {
        let item = credentialItem(isSynchronizable: false)
        let client = RecordingSecurityCredentialKeychainClient(
            copyResponses: [.init(status: errSecItemNotFound, result: nil)],
            updateStatuses: [errSecItemNotFound],
            addStatuses: [errSecSuccess]
        )
        let store = SecurityCredentialKeychainStore(client: client)

        try await store.upsert(item, in: "test.service")

        let attributes = try XCTUnwrap(client.adds.first)
        assertBaseQuery(
            attributes,
            service: "test.service",
            synchronizable: false
        )
        XCTAssertEqual(attributes[kSecAttrAccount] as? String, item.account)
        XCTAssertEqual(attributes[kSecAttrGeneric] as? Data, item.metadata)
        XCTAssertEqual(attributes[kSecValueData] as? Data, item.secret)
        XCTAssertEqual(
            attributes[kSecAttrLabel] as? String,
            SecurityCredentialKeychainStore.itemLabel
        )
        assertCFValue(
            attributes[kSecAttrAccessible],
            equals: kSecAttrAccessibleWhenUnlocked
        )
        XCTAssertNil(attributes[kSecAttrAccessGroup])
    }

    func testSynchronizationChangeRestoresTheOriginalItemWhenAddFails() async throws {
        let original = credentialItem(isSynchronizable: false)
        let replacement = CredentialKeychainItem(
            account: original.account,
            metadata: Data("replacement-metadata".utf8),
            secret: Data("replacement-secret".utf8),
            isSynchronizable: true
        )
        let client = RecordingSecurityCredentialKeychainClient(
            copyResponses: [
                .init(
                    status: errSecSuccess,
                    result: keychainDictionary(for: original) as CFDictionary
                )
            ],
            addStatuses: [errSecDuplicateItem, errSecSuccess],
            deleteStatuses: [errSecSuccess]
        )
        let store = SecurityCredentialKeychainStore(client: client)

        do {
            try await store.upsert(replacement, in: "test.service")
            XCTFail("Expected the replacement add to fail")
        } catch {
            XCTAssertEqual(
                error as? SecurityCredentialKeychainError,
                .status(errSecDuplicateItem)
            )
        }

        XCTAssertTrue(client.updates.isEmpty)
        XCTAssertEqual(client.deletes.count, 1)
        let deleteQuery = try XCTUnwrap(client.deletes.first)
        assertBaseQuery(deleteQuery, service: "test.service")
        XCTAssertEqual(deleteQuery[kSecAttrAccount] as? String, original.account)

        XCTAssertEqual(client.adds.count, 2)
        assertAddedItem(client.adds[0], equals: replacement)
        assertAddedItem(client.adds[1], equals: original)
    }

    func testDeletesTreatMissingItemsAsSuccessAndPropagateOtherStatuses() async throws {
        let client = RecordingSecurityCredentialKeychainClient(
            deleteStatuses: [
                errSecItemNotFound,
                errSecItemNotFound,
                errSecInteractionNotAllowed,
            ]
        )
        let store = SecurityCredentialKeychainStore(client: client)

        try await store.delete(
            account: "credential-account",
            in: "test.service"
        )
        try await store.deleteAll(in: "test.service")
        do {
            try await store.deleteAll(in: "test.service")
            XCTFail("Expected a non-missing Security status to propagate")
        } catch {
            XCTAssertEqual(
                error as? SecurityCredentialKeychainError,
                .status(errSecInteractionNotAllowed)
            )
        }

        XCTAssertEqual(client.deletes.count, 3)
        XCTAssertEqual(
            client.deletes[0][kSecAttrAccount] as? String,
            "credential-account"
        )
        XCTAssertNil(client.deletes[1][kSecAttrAccount])
        XCTAssertNil(client.deletes[2][kSecAttrAccount])
        for query in client.deletes {
            assertBaseQuery(query, service: "test.service")
            XCTAssertNil(query[kSecAttrAccessGroup])
        }
    }

    private func assertAddedItem(
        _ attributes: [CFString: Any],
        equals item: CredentialKeychainItem,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            attributes[kSecAttrAccount] as? String,
            item.account,
            file: file,
            line: line
        )
        XCTAssertEqual(
            attributes[kSecAttrGeneric] as? Data,
            item.metadata,
            file: file,
            line: line
        )
        XCTAssertEqual(
            attributes[kSecValueData] as? Data,
            item.secret,
            file: file,
            line: line
        )
        XCTAssertEqual(
            attributes[kSecAttrSynchronizable] as? Bool,
            item.isSynchronizable,
            file: file,
            line: line
        )
        assertCFValue(
            attributes[kSecAttrAccessible],
            equals: kSecAttrAccessibleWhenUnlocked,
            file: file,
            line: line
        )
    }

    private func assertBaseQuery(
        _ query: [CFString: Any],
        service: String,
        synchronizable: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertCFValue(
            query[kSecClass],
            equals: kSecClassGenericPassword,
            file: file,
            line: line
        )
        XCTAssertEqual(
            query[kSecAttrService] as? String,
            service,
            file: file,
            line: line
        )
        if let synchronizable {
            XCTAssertEqual(
                query[kSecAttrSynchronizable] as? Bool,
                synchronizable,
                file: file,
                line: line
            )
        } else {
            assertCFValue(
                query[kSecAttrSynchronizable],
                equals: kSecAttrSynchronizableAny,
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            query[kSecUseDataProtectionKeychain] as? Bool,
            true,
            file: file,
            line: line
        )
    }

    private func assertCFValue(
        _ actual: Any?,
        equals expected: CFTypeRef,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected Core Foundation value", file: file, line: line)
            return
        }
        XCTAssertTrue(
            CFEqual(actual as CFTypeRef, expected),
            file: file,
            line: line
        )
    }

    private func credentialItem(
        isSynchronizable: Bool
    ) -> CredentialKeychainItem {
        CredentialKeychainItem(
            account: "credential-account",
            metadata: Data("metadata".utf8),
            secret: Data("secret".utf8),
            isSynchronizable: isSynchronizable
        )
    }

    private func keychainDictionary(
        for item: CredentialKeychainItem
    ) -> [CFString: Any] {
        keychainDictionary(
            account: item.account,
            metadata: item.metadata,
            secret: item.secret,
            isSynchronizable: item.isSynchronizable
        )
    }

    private func keychainDictionary(
        account: String,
        metadata: Data,
        secret: Data? = nil,
        isSynchronizable: Bool
    ) -> [CFString: Any] {
        var dictionary: [CFString: Any] = [
            kSecAttrAccount: account,
            kSecAttrGeneric: metadata,
            kSecAttrSynchronizable: NSNumber(value: isSynchronizable),
        ]
        if let secret {
            dictionary[kSecValueData] = secret
        }
        return dictionary
    }
}

private final class RecordingSecurityCredentialKeychainClient:
    SecurityCredentialKeychainClient,
    @unchecked Sendable
{
    struct CopyResponse {
        let status: OSStatus
        let result: CFTypeRef?
    }

    struct Update {
        let query: [CFString: Any]
        let attributes: [CFString: Any]
    }

    private let lock = NSLock()
    private var queuedCopyResponses: [CopyResponse]
    private var queuedUpdateStatuses: [OSStatus]
    private var queuedAddStatuses: [OSStatus]
    private var queuedDeleteStatuses: [OSStatus]
    private var recordedCopyQueries: [[CFString: Any]] = []
    private var recordedUpdates: [Update] = []
    private var recordedAdds: [[CFString: Any]] = []
    private var recordedDeletes: [[CFString: Any]] = []

    init(
        copyResponses: [CopyResponse] = [],
        updateStatuses: [OSStatus] = [],
        addStatuses: [OSStatus] = [],
        deleteStatuses: [OSStatus] = []
    ) {
        queuedCopyResponses = copyResponses
        queuedUpdateStatuses = updateStatuses
        queuedAddStatuses = addStatuses
        queuedDeleteStatuses = deleteStatuses
    }

    var copyQueries: [[CFString: Any]] {
        withLock { recordedCopyQueries }
    }

    var updates: [Update] {
        withLock { recordedUpdates }
    }

    var adds: [[CFString: Any]] {
        withLock { recordedAdds }
    }

    var deletes: [[CFString: Any]] {
        withLock { recordedDeletes }
    }

    func copyMatching(
        _ query: [CFString: Any]
    ) -> (status: OSStatus, result: CFTypeRef?) {
        withLock {
            recordedCopyQueries.append(query)
            return queuedCopyResponses.isEmpty
                ? (errSecItemNotFound, nil)
                : {
                    let response = queuedCopyResponses.removeFirst()
                    return (response.status, response.result)
                }()
        }
    }

    func update(
        _ query: [CFString: Any],
        attributes: [CFString: Any]
    ) -> OSStatus {
        withLock {
            recordedUpdates.append(Update(query: query, attributes: attributes))
            return queuedUpdateStatuses.isEmpty
                ? errSecItemNotFound
                : queuedUpdateStatuses.removeFirst()
        }
    }

    func add(_ attributes: [CFString: Any]) -> OSStatus {
        withLock {
            recordedAdds.append(attributes)
            return queuedAddStatuses.isEmpty
                ? errSecSuccess
                : queuedAddStatuses.removeFirst()
        }
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        withLock {
            recordedDeletes.append(query)
            return queuedDeleteStatuses.isEmpty
                ? errSecSuccess
                : queuedDeleteStatuses.removeFirst()
        }
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
