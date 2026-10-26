import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCredentialTests: XCTestCase {
    func testCredentialOriginKeepsSchemeAndNondefaultPortInsideTheBoundary() throws {
        let secure = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://example.com/login")))
        )
        let insecure = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "http://example.com/login")))
        )
        let alternatePort = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://example.com:8443/login")))
        )
        let ipv6 = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://[::1]:8443/login")))
        )

        XCTAssertNotEqual(secure, insecure)
        XCTAssertNotEqual(secure, alternatePort)
        XCTAssertEqual(alternatePort.description, "https://example.com:8443")
        XCTAssertEqual(ipv6.description, "https://[::1]:8443")
        XCTAssertTrue(secure.isSecure)
        XCTAssertFalse(insecure.isSecure)
        XCTAssertNil(CredentialOrigin(url: try XCTUnwrap(URL(string: "ftp://example.com/file"))))
    }

    func testCredentialOriginRejectsPercentEscapedHostsInsteadOfDecodingThemTwice() throws {
        XCTAssertNil(CredentialOrigin(url: try XCTUnwrap(URL(string: "https://a%40b.com/login"))))
        XCTAssertNil(CredentialOrigin(url: try XCTUnwrap(URL(string: "https://a%2Fb.com/login"))))
        XCTAssertNil(CredentialOrigin(url: try XCTUnwrap(URL(string: "https://[fe80::1%25en0]/login"))))
        XCTAssertNil(CredentialOrigin(url: try XCTUnwrap(URL(string: "https://%3A%3A1/login"))))
    }

    func testLegacyCredentialDescriptorDecodesAsAWebFormCredential() throws {
        let spaceID = UUID()
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://example.com")))
        )
        let descriptor = CredentialDescriptor(
            spaceID: spaceID,
            origin: origin,
            username: "legacy",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let encoded = try JSONEncoder().encode(descriptor)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "scope")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CredentialDescriptor.self, from: legacyData)

        XCTAssertEqual(decoded.scope, .webForm)
    }

    func testDisabledSpaceDoesNotOfferOrSaveCrestCredentials() async throws {
        var seed = SessionState.Seed.preview
        let space = try XCTUnwrap(seed.spaces.first)
        seed.spaces[0].settings.credentialPreferences = CredentialPreferences(
            isEnabled: false, syncsCrestPasswordsWithICloud: true, alsoOffersSaveToSystemPasswords: false)
        let vault = InMemoryCredentialVault()
        let store = BrowserStore(
            seed: seed,
            credentialVault: vault
        )
        let origin = try XCTUnwrap(
            CredentialOrigin(
                url: try XCTUnwrap(
                    URL(string: "https://accounts.crest.test/login")
                )
            )
        )
        let stored = makeCredential(
            spaceID: space.id,
            origin: origin,
            username: "saved-user",
            password: "saved-secret"
        )
        try await vault.save(stored, in: space.id)

        let suggestions = try await store.credentialSuggestions(
            for: try XCTUnwrap(URL(string: origin.description)),
            in: space.id
        )
        XCTAssertTrue(suggestions.isEmpty)

        let protectionSpace = BrowserHTTPAuthenticationProtectionSpace(
            origin: origin,
            credentialScope: .httpBasic(realm: "Members")
        )
        let reusedHTTPAuthentication =
            try await store
            .httpAuthenticationCredential(
                for: protectionSpace,
                in: space.id
            )
        XCTAssertNil(
            reusedHTTPAuthentication
        )

        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "new-user",
            password: "new-secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: .now
        )
        do {
            _ = try await store.credentialSavePlan(
                for: candidate,
                in: space.id
            )
            XCTFail("A disabled manager must reject a stale save prompt")
        } catch {
            XCTAssertEqual(
                error as? CredentialVaultError,
                .credentialManagerDisabled
            )
        }
    }

    func testKeychainVaultUsesAnExactServiceNamespaceBeforeLookup() async throws {
        let work = UUID()
        let personal = UUID()
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://example.com")))
        )
        let itemStore = RecordingCredentialKeychainStore()
        let vault = KeychainCredentialVault(store: itemStore, servicePrefix: "test.crest")
        let workCredential = makeCredential(
            spaceID: work,
            origin: origin,
            username: "person",
            password: "work-secret",
            isSynchronizable: true
        )
        let personalCredential = makeCredential(
            spaceID: personal,
            origin: origin,
            username: "person",
            password: "personal-secret"
        )

        try await vault.save(workCredential, in: work)
        try await vault.save(personalCredential, in: personal)
        _ = try await vault.descriptors(matching: origin, in: work)
        _ = try await vault.credential(id: workCredential.descriptor.id, in: personal)

        let workService = CredentialKeychainNamespace.service(for: work, prefix: "test.crest")
        let personalService = CredentialKeychainNamespace.service(for: personal, prefix: "test.crest")
        let requests = await itemStore.requests

        XCTAssertTrue(requests.contains(.upsert(service: workService)))
        XCTAssertTrue(requests.contains(.upsert(service: personalService)))
        XCTAssertTrue(requests.contains(.descriptorItems(service: workService)))
        XCTAssertFalse(
            requests.contains(.items(service: workService)),
            "Listing password metadata must not read every Keychain secret."
        )
        XCTAssertTrue(
            requests.contains(
                .item(
                    service: personalService,
                    account: workCredential.descriptor.id.uuidString.lowercased()
                )
            )
        )
        XCTAssertFalse(
            requests.contains { request in
                request.service == CredentialKeychainNamespace.productionPrefix
            })

        let storedWorkItemResult = await itemStore.storedItem(
            service: workService,
            account: workCredential.descriptor.id.uuidString.lowercased()
        )
        let storedWorkItem = try XCTUnwrap(storedWorkItemResult)
        XCTAssertTrue(storedWorkItem.isSynchronizable)
        XCTAssertEqual(String(data: storedWorkItem.secret, encoding: .utf8), "work-secret")
        XCTAssertFalse(
            String(data: storedWorkItem.metadata, encoding: .utf8)?.contains("work-secret") == true
        )
    }

    func testKeychainVaultMigratesSynchronizationWithoutChangingTheSecretOrNamespace() async throws {
        let spaceID = UUID()
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://example.com")))
        )
        let itemStore = RecordingCredentialKeychainStore()
        let vault = KeychainCredentialVault(store: itemStore, servicePrefix: "test.crest")
        let credential = makeCredential(
            spaceID: spaceID,
            origin: origin,
            username: "person",
            password: "unchanged-secret"
        )

        try await vault.save(credential, in: spaceID)
        try await vault.setSynchronizable(true, in: spaceID)

        let service = CredentialKeychainNamespace.service(for: spaceID, prefix: "test.crest")
        let storedItemResult = await itemStore.storedItem(
            service: service,
            account: credential.descriptor.id.uuidString.lowercased()
        )
        let storedItem = try XCTUnwrap(storedItemResult)
        let storedDescriptor = try JSONDecoder().decode(
            CredentialDescriptor.self,
            from: storedItem.metadata
        )
        XCTAssertTrue(storedItem.isSynchronizable)
        XCTAssertTrue(storedDescriptor.isSynchronizable)
        XCTAssertEqual(String(data: storedItem.secret, encoding: .utf8), "unchanged-secret")
    }

    func testKeychainVaultFailsClosedForCrossSpaceMetadata() async throws {
        let work = UUID()
        let personal = UUID()
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://example.com")))
        )
        let itemStore = RecordingCredentialKeychainStore()
        let vault = KeychainCredentialVault(store: itemStore, servicePrefix: "test.crest")
        let hostileDescriptor = makeCredential(
            spaceID: personal,
            origin: origin,
            username: "intruder",
            password: "secret"
        ).descriptor
        let hostileItem = CredentialKeychainItem(
            account: hostileDescriptor.id.uuidString.lowercased(),
            metadata: try JSONEncoder().encode(hostileDescriptor),
            secret: Data("secret".utf8),
            isSynchronizable: false
        )
        await itemStore.upsert(
            hostileItem,
            in: CredentialKeychainNamespace.service(for: work, prefix: "test.crest")
        )

        let offered = try await vault.descriptors(matching: origin, in: work)
        XCTAssertTrue(offered.isEmpty, "Cross-Space metadata must never be offered")
        let unreadableCount = try await vault.unreadableCredentialCount(in: work)
        XCTAssertEqual(unreadableCount, 1)
        do {
            _ = try await vault.credential(id: hostileDescriptor.id, in: work)
            XCTFail("Expected malformed cross-Space metadata to fail closed")
        } catch {
            XCTAssertEqual(error as? CredentialVaultError, .malformedStoredCredential)
        }
    }

    func testBrowserStoreScopesSuggestionsAndSecretLookupToTheSelectedSpace() async throws {
        let vault = InMemoryCredentialVault()
        let store = BrowserStore(
            seed: .preview,
            credentialVault: vault
        )
        let spaces = store.spaceModels
        let work = try XCTUnwrap(spaces.first)
        let personal = try XCTUnwrap(spaces.dropFirst().first)
        let url = try XCTUnwrap(URL(string: "https://accounts.example.com/sign-in"))

        store.selectSpace(work.id)
        let workDescriptor = try await store.saveCredential(
            username: "same-user",
            password: "work-secret",
            for: url
        )

        store.selectSpace(personal.id)
        let personalDescriptor = try await store.saveCredential(
            username: "same-user",
            password: "personal-secret",
            for: url
        )
        let personalSuggestions = try await store.credentialSuggestions(for: url)
        let personalInventory = try await store.savedCredentialDescriptors(in: personal.id)
        let personalSecret = try await store.credential(id: personalDescriptor.id)
        let workSecretFromPersonal = try await store.credential(id: workDescriptor.id)
        XCTAssertEqual(personalSuggestions, [personalDescriptor])
        XCTAssertEqual(personalInventory, [personalDescriptor])
        XCTAssertEqual(personalSecret?.password, "personal-secret")
        XCTAssertNil(workSecretFromPersonal)

        store.selectSpace(work.id)
        let workSuggestions = try await store.credentialSuggestions(for: url)
        let workInventory = try await store.savedCredentialDescriptors(in: work.id)
        let workSecret = try await store.credential(id: workDescriptor.id)
        let personalSecretFromWork = try await store.credential(id: personalDescriptor.id)
        XCTAssertEqual(workSuggestions, [workDescriptor])
        XCTAssertEqual(workInventory, [workDescriptor])
        XCTAssertEqual(workSecret?.password, "work-secret")
        XCTAssertNil(personalSecretFromWork)
    }

    func testBrowserStoreDoesNotSuggestOrSavePasswordsOnHTTP() async throws {
        let store = BrowserStore(
            seed: .preview,
            credentialVault: InMemoryCredentialVault()
        )
        let insecureURL = try XCTUnwrap(URL(string: "http://example.com/login"))

        let insecureSuggestions = try await store.credentialSuggestions(for: insecureURL)
        XCTAssertEqual(insecureSuggestions, [])
        do {
            _ = try await store.saveCredential(
                username: "person",
                password: "secret",
                for: insecureURL
            )
            XCTFail("Expected insecure password storage to be rejected")
        } catch {
            XCTAssertEqual(error as? CredentialVaultError, .insecureOrigin)
        }
    }

    func testSensitiveCredentialRevealAuthenticatesBeforeReadingTheExactSpace() async throws {
        let vault = InMemoryCredentialVault()
        let store = BrowserStore(
            seed: .preview,
            credentialVault: vault
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let personal = try XCTUnwrap(store.spaceModels.dropFirst().first)
        let descriptor = try await store.saveCredential(
            username: "person@example.com",
            password: "work-secret",
            for: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")),
            in: work.id
        )
        let deniedAuthenticator = StubBrowserCredentialAuthenticator(allowsAccess: false)
        let deniedAccess = BrowserCredentialSensitiveAccess(
            browser: store,
            authenticator: deniedAuthenticator
        )

        do {
            _ = try await deniedAccess.revealCredential(id: descriptor.id, in: work.id)
            XCTFail("A denied local authentication must not reveal a password")
        } catch {
            XCTAssertEqual(
                error as? BrowserCredentialSensitiveAccessError,
                .authenticationDenied
            )
        }
        XCTAssertEqual(deniedAuthenticator.reasons.count, 1)

        let allowedAuthenticator = StubBrowserCredentialAuthenticator(allowsAccess: true)
        let allowedAccess = BrowserCredentialSensitiveAccess(
            browser: store,
            authenticator: allowedAuthenticator
        )
        let exact = try await allowedAccess.revealCredential(
            id: descriptor.id,
            in: work.id
        )
        XCTAssertEqual(exact.password, "work-secret")

        do {
            _ = try await allowedAccess.revealCredential(
                id: descriptor.id,
                in: personal.id
            )
            XCTFail("Authentication must not weaken exact-Space lookup")
        } catch {
            XCTAssertEqual(
                error as? BrowserCredentialSensitiveAccessError,
                .missingCredential
            )
        }
    }

    func testAuthenticatedCredentialExportContainsOnlyOneSpace() async throws {
        let vault = InMemoryCredentialVault()
        let store = BrowserStore(
            seed: .preview,
            credentialVault: vault
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let personal = try XCTUnwrap(store.spaceModels.dropFirst().first)
        _ = try await store.saveCredential(
            username: "work,person@example.com",
            password: "line one\n\"line two\"",
            for: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")),
            in: work.id,
            displayName: "Crest, Account"
        )
        _ = try await store.saveCredential(
            username: "personal@example.com",
            password: "personal-secret-must-not-export",
            for: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")),
            in: personal.id
        )
        let authenticator = StubBrowserCredentialAuthenticator(allowsAccess: true)
        let access = BrowserCredentialSensitiveAccess(
            browser: store,
            authenticator: authenticator
        )

        let exported = try await access.exportCredentials(in: work.id)
        let csv = try XCTUnwrap(String(data: exported.contents, encoding: .utf8))

        XCTAssertTrue(csv.contains("\"work,person@example.com\""))
        XCTAssertFalse(csv.contains("personal-secret-must-not-export"))
        XCTAssertEqual(authenticator.reasons.count, 1)
    }

    private func makeCredential(
        spaceID: UUID,
        origin: CredentialOrigin,
        username: String,
        password: String,
        isSynchronizable: Bool = false
    ) -> BrowserCredential {
        BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: spaceID,
                origin: origin,
                username: username,
                createdAt: Date(timeIntervalSince1970: 1_000),
                isSynchronizable: isSynchronizable
            ),
            password: password
        )
    }
}

@MainActor
private final class StubBrowserCredentialAuthenticator: BrowserDeviceAuthenticating {
    let allowsAccess: Bool
    private(set) var reasons: [String] = []

    init(allowsAccess: Bool) {
        self.allowsAccess = allowsAccess
    }

    func authenticate(reason: String) async throws -> Bool {
        reasons.append(reason)
        return allowsAccess
    }
}

private actor RecordingCredentialKeychainStore: CredentialKeychainStoring {
    enum Request: Equatable, Sendable {
        case descriptorItems(service: String)
        case items(service: String)
        case item(service: String, account: String)
        case upsert(service: String)
        case delete(service: String, account: String)
        case deleteAll(service: String)

        var service: String {
            switch self {
            case .descriptorItems(let service), .items(let service),
                .upsert(let service), .deleteAll(let service):
                service
            case .item(let service, _), .delete(let service, _):
                service
            }
        }
    }

    private var storage: [String: [String: CredentialKeychainItem]] = [:]
    private(set) var requests: [Request] = []

    func descriptorItems(in service: String) -> [CredentialKeychainDescriptorItem] {
        requests.append(.descriptorItems(service: service))
        return storage[service, default: [:]].values.map {
            CredentialKeychainDescriptorItem(
                account: $0.account,
                metadata: $0.metadata,
                isSynchronizable: $0.isSynchronizable
            )
        }
    }

    func items(in service: String) -> [CredentialKeychainItem] {
        requests.append(.items(service: service))
        return Array(storage[service, default: [:]].values)
    }

    func item(account: String, in service: String) -> CredentialKeychainItem? {
        requests.append(.item(service: service, account: account))
        return storage[service]?[account]
    }

    func upsert(_ item: CredentialKeychainItem, in service: String) {
        requests.append(.upsert(service: service))
        storage[service, default: [:]][item.account] = item
    }

    func delete(account: String, in service: String) {
        requests.append(.delete(service: service, account: account))
        storage[service]?[account] = nil
    }

    func deleteAll(in service: String) {
        requests.append(.deleteAll(service: service))
        storage[service] = nil
    }

    func storedItem(service: String, account: String) -> CredentialKeychainItem? {
        storage[service]?[account]
    }
}

final class BrowserCredentialInventoryTests: XCTestCase {
}
