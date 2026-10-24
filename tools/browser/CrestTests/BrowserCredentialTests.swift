import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCredentialTests: XCTestCase {
    func testStrongPasswordGeneratorDrawsEveryCharacterClassFromTheCoreRecipe() throws {
        let passwords = try (0..<64).map { _ in
            try BrowserStrongPasswordGenerator.generate(from: CrestCore().query(StrongPassword(length: nil)))
        }

        XCTAssertEqual(Set(passwords).count, passwords.count)
        for password in passwords {
            XCTAssertEqual(password.count, 20)
            XCTAssertTrue(password.allSatisfy(\.isASCII))
            XCTAssertTrue(password.contains(where: \.isLowercase))
            XCTAssertTrue(password.contains(where: \.isUppercase))
            XCTAssertTrue(password.contains(where: \.isNumber))
            XCTAssertTrue(password.contains { "-_.!@#$%^&*+=".contains($0) })
            XCTAssertFalse(password.contains(where: \.isWhitespace))
        }
    }

    func testCredentialOriginRejectsOpaqueWebKitOriginsBeforeURLConstruction() throws {
        XCTAssertNil(
            CredentialOrigin(
                securityProtocol: "data",
                host: "",
                port: 0
            ))
        XCTAssertNil(
            CredentialOrigin(
                securityProtocol: "https:",
                host: "example.com",
                port: 443
            ))
        XCTAssertEqual(
            CredentialOrigin(
                securityProtocol: "HTTPS",
                host: "example.com",
                port: 443
            )?.description,
            "https://example.com"
        )
    }

    func testCredentialOriginCanonicalizesSchemeHostDefaultPortAndIDN() throws {
        let ordinary = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "HTTPS://EXAMPLE.COM:443/login#form")))
        )
        let unicode = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://bücher.example/sign-in")))
        )
        let punycode = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://xn--bcher-kva.example:443/account")))
        )

        XCTAssertEqual(ordinary.description, "https://example.com")
        XCTAssertEqual(ordinary.port, 443)
        XCTAssertEqual(unicode, punycode)
        XCTAssertEqual(unicode.host, "xn--bcher-kva.example")
    }

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

    func testCredentialOriginDecodingRejectsNoncanonicalOrNonHTTPData() throws {
        let decoder = JSONDecoder()
        let invalidScheme = Data(#"{"scheme":"ftp","host":"example.com","port":21}"#.utf8)
        let uppercaseHost = Data(#"{"scheme":"https","host":"EXAMPLE.com","port":443}"#.utf8)
        let valid = Data(#"{"scheme":"https","host":"example.com","port":443}"#.utf8)

        XCTAssertThrowsError(try decoder.decode(CredentialOrigin.self, from: invalidScheme))
        XCTAssertThrowsError(try decoder.decode(CredentialOrigin.self, from: uppercaseHost))
        XCTAssertEqual(
            try decoder.decode(CredentialOrigin.self, from: valid).description,
            "https://example.com"
        )
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

    func testHTTPAuthenticationCredentialsNeverAppearInFormSuggestions() async throws {
        let spaceID = UUID()
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")))
        )
        let vault = InMemoryCredentialVault()
        let formCredential = makeCredential(
            spaceID: spaceID,
            origin: origin,
            username: "form-user",
            password: "form-secret"
        )
        let httpCredential = BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: spaceID,
                origin: origin,
                scope: .httpBasic(realm: "Members"),
                username: "http-user",
                createdAt: Date(timeIntervalSince1970: 2_000)
            ),
            password: "http-secret"
        )

        try await vault.save(formCredential, in: spaceID)
        try await vault.save(httpCredential, in: spaceID)

        let formDescriptors = await vault.descriptors(matching: origin, in: spaceID)
        let httpDescriptors = await vault.descriptors(
            matching: BrowserHTTPAuthenticationProtectionSpace(
                origin: origin,
                credentialScope: .httpBasic(realm: "Members")
            ),
            in: spaceID
        )

        XCTAssertEqual(formDescriptors, [formCredential.descriptor])
        XCTAssertEqual(httpDescriptors, [httpCredential.descriptor])
    }

    func testBrowserStoreReusesHTTPAuthenticationOnlyInTheExactSpaceAndRealm() async throws {
        let vault = InMemoryCredentialVault()
        let store = BrowserStore(
            seed: .preview,
            credentialVault: vault
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let personal = try XCTUnwrap(store.spaceModels.dropFirst().first)
        let workMembers = try XCTUnwrap(
            BrowserHTTPAuthenticationProtectionSpace(
                URLProtectionSpace(
                    host: "accounts.crest.test",
                    port: 443,
                    protocol: "https",
                    realm: "Members",
                    authenticationMethod: NSURLAuthenticationMethodHTTPBasic
                )
            )
        )
        let workAdmins = BrowserHTTPAuthenticationProtectionSpace(
            origin: workMembers.origin,
            credentialScope: .httpBasic(realm: "Admins")
        )

        let descriptor = try await store.saveHTTPAuthenticationCredential(
            username: "work-user",
            password: "work-secret",
            protectionSpace: workMembers,
            in: work.id,
            now: Date(timeIntervalSince1970: 3_000)
        )

        let exact = try await store.httpAuthenticationCredential(
            for: workMembers,
            in: work.id
        )
        let wrongRealm = try await store.httpAuthenticationCredential(
            for: workAdmins,
            in: work.id
        )
        let wrongSpace = try await store.httpAuthenticationCredential(
            for: workMembers,
            in: personal.id
        )

        XCTAssertEqual(exact?.descriptor, descriptor)
        XCTAssertEqual(exact?.password, "work-secret")
        XCTAssertNil(wrongRealm)
        XCTAssertNil(wrongSpace)
    }

    func testBrowserStoreNeverSavesOrReusesHTTPAuthenticationOverPlainHTTP() async throws {
        let store = BrowserStore(
            seed: .preview,
            credentialVault: InMemoryCredentialVault()
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let insecure = try XCTUnwrap(
            BrowserHTTPAuthenticationProtectionSpace(
                URLProtectionSpace(
                    host: "accounts.crest.test",
                    port: 80,
                    protocol: "http",
                    realm: "Members",
                    authenticationMethod: NSURLAuthenticationMethodHTTPBasic
                )
            )
        )

        do {
            _ = try await store.saveHTTPAuthenticationCredential(
                username: "person",
                password: "secret",
                protectionSpace: insecure,
                in: work.id
            )
            XCTFail("Expected insecure HTTP authentication storage to be rejected")
        } catch {
            XCTAssertEqual(error as? CredentialVaultError, .insecureOrigin)
        }
        let stored = try await store.httpAuthenticationCredential(
            for: insecure,
            in: work.id
        )
        XCTAssertNil(stored)
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

    func testInMemoryVaultNeverReturnsAnotherSpacesCredential() async throws {
        let work = UUID()
        let personal = UUID()
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.example.com/login")))
        )
        let vault = InMemoryCredentialVault()
        let workCredential = makeCredential(
            spaceID: work,
            origin: origin,
            username: "same-user",
            password: "work-secret"
        )
        let personalCredential = makeCredential(
            spaceID: personal,
            origin: origin,
            username: "same-user",
            password: "personal-secret",
            isSynchronizable: true
        )

        try await vault.save(workCredential, in: work)
        try await vault.save(personalCredential, in: personal)

        let workDescriptors = await vault.descriptors(matching: origin, in: work)
        let personalDescriptors = await vault.descriptors(matching: origin, in: personal)
        let workResult = await vault.credential(id: workCredential.descriptor.id, in: work)
        let crossSpaceResult = await vault.credential(
            id: workCredential.descriptor.id,
            in: personal
        )
        XCTAssertEqual(workDescriptors, [workCredential.descriptor])
        XCTAssertEqual(personalDescriptors, [personalCredential.descriptor])
        XCTAssertEqual(workResult?.password, "work-secret")
        XCTAssertNil(crossSpaceResult)

        await vault.deleteAll(in: personal)
        let workAfterPersonalDeletion = await vault.credential(
            id: workCredential.descriptor.id,
            in: work
        )
        XCTAssertNotNil(workAfterPersonalDeletion)
    }

    func testVaultRejectsCredentialWhoseDescriptorNamesAnotherSpace() async throws {
        let work = UUID()
        let personal = UUID()
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://example.com")))
        )
        let vault = InMemoryCredentialVault()
        let credential = makeCredential(
            spaceID: work,
            origin: origin,
            username: "person",
            password: "secret"
        )

        do {
            try await vault.save(credential, in: personal)
            XCTFail("Expected the vault to reject a cross-Space write")
        } catch {
            XCTAssertEqual(
                error as? CredentialVaultError,
                .spaceMismatch(expected: personal, actual: work)
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

        do {
            _ = try await vault.descriptors(matching: origin, in: work)
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

    func testSpaceSynchronizationPreferenceMigratesExistingCredentialsWithoutTouchingOtherSpaces() async throws {
        let vault = InMemoryCredentialVault()
        let store = BrowserStore(
            seed: .preview,
            credentialVault: vault
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let personal = try XCTUnwrap(store.spaceModels.dropFirst().first)
        let url = try XCTUnwrap(URL(string: "https://accounts.example.com/sign-in"))
        let workDescriptor = try await store.saveCredential(
            username: "work-user",
            password: "work-secret",
            for: url,
            in: work.id
        )
        let personalDescriptor = try await store.saveCredential(
            username: "personal-user",
            password: "personal-secret",
            for: url,
            in: personal.id
        )

        XCTAssertTrue(workDescriptor.isSynchronizable)
        XCTAssertTrue(personalDescriptor.isSynchronizable)
        try await store.setCrestPasswordSynchronization(false, in: work.id)

        let migratedWork = try await store.credential(id: workDescriptor.id, in: work.id)
        let untouchedPersonal = try await store.credential(id: personalDescriptor.id, in: personal.id)
        XCTAssertEqual(migratedWork?.password, "work-secret")
        XCTAssertFalse(try XCTUnwrap(migratedWork).descriptor.isSynchronizable)
        XCTAssertTrue(try XCTUnwrap(untouchedPersonal).descriptor.isSynchronizable)
        XCTAssertFalse(
            try XCTUnwrap(store.spaceModel(work.id))
                .settings.credentialPreferences.syncsCrestPasswordsWithICloud)
        XCTAssertTrue(
            try XCTUnwrap(store.spaceModel(personal.id))
                .settings.credentialPreferences.syncsCrestPasswordsWithICloud)
    }

    func testSynchronizationCompletionRespectsProfileIdentityAndNewerPreferences() async throws {
        for replacesProfile in [false, true] {
            let vault = CredentialSynchronizationInterleavingVault()
            let store = BrowserStore(
                seed: .preview, credentialVault: vault)
            let otherWindow = store.makeWindowStore()
            let original = try XCTUnwrap(store.shownSpace)
            vault.duringSynchronization = {
                var preferences = original.settings.credentialPreferences
                preferences.isEnabled = false
                if replacesProfile { otherWindow.replaceProfileForTesting(of: original.id) }
                otherWindow.updateCredentialPreferences(preferences, in: original.id)
            }

            do {
                try await store.setCrestPasswordSynchronization(false, in: original.id)
                XCTAssertFalse(replacesProfile, "A replacement profile must reject the stale completion")
            } catch {
                XCTAssertTrue(replacesProfile)
                XCTAssertEqual(error as? CredentialVaultError, .missingSpace)
            }

            let preferences = try XCTUnwrap(store.spaceModel(original.id)).settings.credentialPreferences
            XCTAssertFalse(preferences.isEnabled)
            XCTAssertEqual(preferences.syncsCrestPasswordsWithICloud, replacesProfile)
        }
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

    func testFormCredentialLifecycleCreatesOnlyInTheOwningSpaceAndSuppressesAnUnchangedPassword() async throws {
        let vault = InMemoryCredentialVault()
        let store = BrowserStore(
            seed: .preview,
            credentialVault: vault
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let personal = try XCTUnwrap(store.spaceModels.dropFirst().first)
        let submittedAt = Date(timeIntervalSince1970: 4_000)
        let url = try XCTUnwrap(URL(string: "https://accounts.crest.test/login"))
        let origin = try XCTUnwrap(CredentialOrigin(url: url))
        let candidate = makeCandidate(
            origin: origin,
            username: "person@example.com",
            password: "unchanged-secret",
            submittedAt: submittedAt
        )

        let initialPlan = try await store.credentialSavePlan(
            for: candidate,
            in: work.id,
            now: submittedAt
        )
        XCTAssertTrue(initialPlan is BrowserCredentialCreatePlan)

        let result = try await store.commitCredentialSave(
            candidate,
            in: work.id,
            now: submittedAt
        )
        let unchangedPlan = try await store.credentialSavePlan(
            for: candidate,
            in: work.id,
            now: submittedAt
        )

        XCTAssertEqual(result.disposition, .created)
        guard let existing = (unchangedPlan as? BrowserCredentialAlreadyStoredPlan)?.existing else {
            return XCTFail("An identical submitted password should not prompt again")
        }
        XCTAssertEqual(existing.id, result.descriptor.id)
        let workSuggestions = try await store.credentialSuggestions(for: url, in: work.id)
        let personalSuggestions = try await store.credentialSuggestions(for: url, in: personal.id)
        XCTAssertEqual(workSuggestions, [result.descriptor])
        XCTAssertEqual(personalSuggestions, [])
    }

    func testChangedFormPasswordUpdatesTheExistingRecordWithoutChangingItsIdentity() async throws {
        let store = BrowserStore(
            seed: .preview,
            credentialVault: InMemoryCredentialVault()
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let url = try XCTUnwrap(URL(string: "https://accounts.crest.test/login"))
        let origin = try XCTUnwrap(CredentialOrigin(url: url))
        let createdAt = Date(timeIntervalSince1970: 5_000)
        let updatedAt = createdAt.addingTimeInterval(10)
        let original = makeCandidate(
            origin: origin,
            username: "person@example.com",
            password: "original-secret",
            submittedAt: createdAt
        )
        let created = try await store.commitCredentialSave(
            original,
            in: work.id,
            now: createdAt
        )
        let changed = makeCandidate(
            origin: origin,
            username: "PERSON@example.com",
            password: "updated-secret",
            submittedAt: updatedAt
        )

        let plan = try await store.credentialSavePlan(
            for: changed,
            in: work.id,
            now: updatedAt
        )
        guard let existing = (plan as? BrowserCredentialUpdatePlan)?.existing else {
            return XCTFail("A changed password for the same username should update")
        }
        XCTAssertEqual(existing.id, created.descriptor.id)

        let updated = try await store.commitCredentialSave(
            changed,
            in: work.id,
            now: updatedAt
        )
        let inventory = try await store.savedCredentialDescriptors(in: work.id)
        let stored = try await store.credential(id: updated.descriptor.id, in: work.id)

        XCTAssertEqual(updated.disposition, .updated)
        XCTAssertEqual(updated.descriptor.id, created.descriptor.id)
        XCTAssertEqual(updated.descriptor.createdAt, createdAt)
        XCTAssertEqual(updated.descriptor.updatedAt, updatedAt)
        XCTAssertEqual(inventory, [updated.descriptor])
        XCTAssertEqual(stored?.password, "updated-secret")
    }

    func testDeletingACommittedFormCredentialRemovesOnlyTheOwningSpacesSuggestionAndSecret() async throws {
        let store = BrowserStore(
            seed: .preview,
            credentialVault: InMemoryCredentialVault()
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let personal = try XCTUnwrap(store.spaceModels.dropFirst().first)
        let submittedAt = Date(timeIntervalSince1970: 6_000)
        let url = try XCTUnwrap(URL(string: "https://accounts.crest.test/login"))
        let origin = try XCTUnwrap(CredentialOrigin(url: url))
        let candidate = makeCandidate(
            origin: origin,
            username: "person@example.com",
            password: "secret",
            submittedAt: submittedAt
        )
        let workResult = try await store.commitCredentialSave(
            candidate,
            in: work.id,
            now: submittedAt
        )
        let personalResult = try await store.commitCredentialSave(
            candidate,
            in: personal.id,
            now: submittedAt
        )

        try await store.deleteCredential(id: workResult.descriptor.id, in: work.id)

        let workSuggestions = try await store.credentialSuggestions(for: url, in: work.id)
        let deletedWorkCredential = try await store.credential(
            id: workResult.descriptor.id,
            in: work.id
        )
        let personalSuggestions = try await store.credentialSuggestions(for: url, in: personal.id)
        let personalCredential = try await store.credential(
            id: personalResult.descriptor.id,
            in: personal.id
        )
        XCTAssertEqual(workSuggestions, [])
        XCTAssertNil(deletedWorkCredential)
        XCTAssertEqual(personalSuggestions, [personalResult.descriptor])
        XCTAssertEqual(personalCredential?.password, "secret")
    }

    func testStaleAndFutureFormCandidatesAreRejectedWithoutWritingToTheVault() async throws {
        let store = BrowserStore(
            seed: .preview,
            credentialVault: InMemoryCredentialVault()
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let submittedAt = Date(timeIntervalSince1970: 7_000)
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")))
        )
        let stale = makeCandidate(
            origin: origin,
            username: "person@example.com",
            password: "stale-secret",
            submittedAt: submittedAt
        )
        let future = makeCandidate(
            origin: origin,
            username: "person@example.com",
            password: "future-secret",
            submittedAt: submittedAt.addingTimeInterval(1)
        )

        for (candidate, now) in [
            (
                stale,
                // The core keeps a candidate for 45 seconds.
                submittedAt.addingTimeInterval(46)
            ),
            (future, submittedAt),
        ] {
            do {
                _ = try await store.commitCredentialSave(
                    candidate,
                    in: work.id,
                    now: now
                )
                XCTFail("Expected an invalid candidate lifetime to be rejected")
            } catch {
                XCTAssertEqual(error as? CredentialVaultError, .staleSaveCandidate)
            }
        }

        let inventory = try await store.savedCredentialDescriptors(in: work.id)
        XCTAssertEqual(inventory, [])
    }

    func testConcurrentFormCredentialCommitsCoalesceToOneRecord() async throws {
        let store = BrowserStore(
            seed: .preview,
            credentialVault: InMemoryCredentialVault()
        )
        let work = try XCTUnwrap(store.spaceModels.first)
        let submittedAt = Date(timeIntervalSince1970: 8_000)
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")))
        )
        let firstCandidate = makeCandidate(
            origin: origin,
            username: "person@example.com",
            password: "secret",
            submittedAt: submittedAt
        )
        let secondCandidate = makeCandidate(
            origin: origin,
            username: "PERSON@example.com",
            password: "secret",
            submittedAt: submittedAt
        )

        async let first = store.commitCredentialSave(
            firstCandidate,
            in: work.id,
            now: submittedAt
        )
        async let second = store.commitCredentialSave(
            secondCandidate,
            in: work.id,
            now: submittedAt
        )
        let results = try await [first, second]
        let inventory = try await store.savedCredentialDescriptors(in: work.id)

        XCTAssertEqual(Set(results.map(\.descriptor.id)), Set(inventory.map(\.id)))
        XCTAssertEqual(inventory.count, 1)
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

    private func makeCandidate(
        origin: CredentialOrigin,
        username: String,
        password: String,
        submittedAt: Date
    ) -> BrowserCredentialSaveCandidate {
        BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: username,
            password: password,
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: submittedAt
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
    @MainActor
    func testImportedHTTPPasswordRemainsAvailableForManualAccessOnly() async throws {
        let vault = InMemoryCredentialVault()
        let browser = BrowserStore(
            seed: .preview,
            credentialVault: vault
        )
        let space = try XCTUnwrap(browser.spaceModels.first)
        let url = try XCTUnwrap(URL(string: "http://legacy.example/login"))
        let credential = BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: space.id,
                origin: try XCTUnwrap(CredentialOrigin(url: url)),
                username: "legacy-user"
            ),
            password: "synthetic-http-secret"
        )

        try await browser.replaceCredentialInventory([credential], in: space.id)

        let descriptors = try await browser.savedCredentialDescriptors(in: space.id)
        let stored = try await browser.credential(
            id: credential.descriptor.id,
            in: space.id
        )
        let suggestions = try await browser.credentialSuggestions(
            for: url,
            in: space.id
        )
        XCTAssertEqual(descriptors, [credential.descriptor])
        XCTAssertEqual(stored, credential)
        XCTAssertTrue(suggestions.isEmpty)
    }

    @MainActor
    func testAuthenticatedInventoryAndAtomicReplacementStayInsideDestinationSpace() async throws {
        let vault = InMemoryCredentialVault()
        let browser = BrowserStore(
            seed: .preview,
            credentialVault: vault
        )
        let work = try XCTUnwrap(browser.spaceModels.first)
        let personal = try XCTUnwrap(browser.spaceModels.dropFirst().first)
        let origin = try XCTUnwrap(URL(string: "https://isolated.example/login"))
        _ = try await browser.saveCredential(
            username: "work",
            password: "work-secret",
            for: origin,
            in: work.id
        )
        _ = try await browser.saveCredential(
            username: "personal",
            password: "personal-secret",
            for: origin,
            in: personal.id
        )
        let authenticator = StubBrowserCredentialAuthenticator(allowsAccess: true)
        let access = BrowserCredentialSensitiveAccess(
            browser: browser,
            authenticator: authenticator
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: work)

        let inventory = try await access.credentialInventory(
            matching: assignment,
            reason: "Authenticate for a synthetic import test."
        )
        XCTAssertEqual(inventory.map(\.password), ["work-secret"])

        let replacement = BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: work.id,
                origin: try XCTUnwrap(CredentialOrigin(url: origin)),
                username: "replacement",
                createdAt: Date(timeIntervalSince1970: 500)
            ),
            password: "replacement-secret"
        )
        try await browser.replaceCredentialInventory([replacement], in: work.id)
        let workUsernames = try await browser.savedCredentialDescriptors(in: work.id)
            .map(\.username)
        let personalUsernames = try await browser.savedCredentialDescriptors(in: personal.id)
            .map(\.username)

        XCTAssertEqual(workUsernames, ["replacement"])
        XCTAssertEqual(personalUsernames, ["personal"])
        XCTAssertEqual(authenticator.reasons.count, 1)
    }
}

@MainActor
private final class CredentialSynchronizationInterleavingVault: CredentialVault {
    let storage = InMemoryCredentialVault()
    var duringSynchronization: (() -> Void)?

    func descriptors(in spaceID: UUID) async throws -> [CredentialDescriptor] {
        await storage.descriptors(in: spaceID)
    }

    func descriptors(matching origin: CredentialOrigin, in spaceID: UUID) async throws -> [CredentialDescriptor] {
        await storage.descriptors(matching: origin, in: spaceID)
    }

    func descriptors(
        matching protectionSpace: BrowserHTTPAuthenticationProtectionSpace, in spaceID: UUID
    ) async throws -> [CredentialDescriptor] {
        await storage.descriptors(matching: protectionSpace, in: spaceID)
    }

    func credential(id: UUID, in spaceID: UUID) async throws -> BrowserCredential? {
        await storage.credential(id: id, in: spaceID)
    }

    func save(_ credential: BrowserCredential, in spaceID: UUID) async throws {
        try await storage.save(credential, in: spaceID)
    }

    func replaceAll(_ credentials: [BrowserCredential], in spaceID: UUID) async throws {
        try await storage.replaceAll(credentials, in: spaceID)
    }

    func setSynchronizable(_ isSynchronizable: Bool, in spaceID: UUID) async throws {
        await storage.setSynchronizable(isSynchronizable, in: spaceID)
        let callback = duringSynchronization
        duringSynchronization = nil
        callback?()
    }

    func delete(id: UUID, in spaceID: UUID) async throws {
        await storage.delete(id: id, in: spaceID)
    }

    func deleteAll(in spaceID: UUID) async throws {
        await storage.deleteAll(in: spaceID)
    }
}
