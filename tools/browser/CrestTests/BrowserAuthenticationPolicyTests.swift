import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserAuthenticationPolicyTests: XCTestCase {
    /// Foundation's challenge names map onto the core's methods so that only
    /// Basic and Digest reach Crest's credential prompt.
    func testTrustAndClientCertificateChallengesRemainSystemOwned() {
        for method in [
            NSURLAuthenticationMethodServerTrust,
            NSURLAuthenticationMethodClientCertificate,
            NSURLAuthenticationMethodNTLM,
        ] {
            XCTAssertEqual(
                ChallengeHandling(
                    method: AuthenticationMethod(authenticationMethod: method),
                    isProxy: false,
                    previousFailureCount: 0
                ).handling,
                .performDefaultHandling
            )
        }
        XCTAssertEqual(
            ChallengeHandling(
                method: AuthenticationMethod(authenticationMethod: NSURLAuthenticationMethodHTTPDigest),
                isProxy: false,
                previousFailureCount: 0
            ).handling,
            .promptForCredentials
        )
    }

    func testCredentialProtectionSpaceIncludesOriginRealmAndAuthenticationMethod() throws {
        let basic = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 443,
            protocol: "https",
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let digest = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 443,
            protocol: "https",
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPDigest
        )

        let basicScope = try XCTUnwrap(BrowserHTTPAuthenticationProtectionSpace(basic))
        let digestScope = try XCTUnwrap(BrowserHTTPAuthenticationProtectionSpace(digest))

        XCTAssertEqual(basicScope.origin.description, "https://accounts.crest.test")
        XCTAssertEqual(basicScope.credentialScope, .httpBasic(realm: "Members"))
        XCTAssertEqual(digestScope.credentialScope, .httpDigest(realm: "Members"))
        XCTAssertNotEqual(basicScope, digestScope)
    }

    func testCredentialProtectionSpaceRejectsProxyAndNonPasswordChallenges() {
        let trust = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let proxy = URLProtectionSpace(
            proxyHost: "proxy.crest.test",
            port: 8080,
            type: NSURLProtectionSpaceHTTPProxy,
            realm: "Proxy",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        XCTAssertNil(BrowserHTTPAuthenticationProtectionSpace(trust))
        XCTAssertNil(BrowserHTTPAuthenticationProtectionSpace(proxy))
    }

    func testSavedHTTPSCredentialIsReusedOnceAndMarkedUsedOnlyAfterSuccess() async throws {
        let spaceID = UUID()
        let protectionSpace = makeProtectionSpace()
        let scope = try XCTUnwrap(BrowserHTTPAuthenticationProtectionSpace(protectionSpace))
        let stored = makeCredential(
            spaceID: spaceID,
            protectionSpace: scope,
            username: "member",
            password: "stored-secret"
        )
        var prompts = 0
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            loadCredential: { _ in stored },
            saveCredential: { saves.append($0) }
        )

        let resolution = await session.response(
            to: makeChallenge(protectionSpace: protectionSpace)
        ) { _ in
            prompts += 1
            return nil
        }

        XCTAssertEqual(resolution.disposition, .useCredential)
        XCTAssertEqual(resolution.credential?.user, "member")
        XCTAssertEqual(resolution.credential?.password, "stored-secret")
        XCTAssertEqual(prompts, 0)
        XCTAssertTrue(saves.isEmpty)

        await session.authenticationSucceeded()

        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves.first?.replacing, stored.descriptor)
        XCTAssertEqual(saves.first?.password, "stored-secret")
    }

    func testRejectedSavedCredentialPromptsAndReplacesOnlyAfterAcceptedNavigation() async throws {
        let spaceID = UUID()
        let protectionSpace = makeProtectionSpace()
        let scope = try XCTUnwrap(BrowserHTTPAuthenticationProtectionSpace(protectionSpace))
        let stored = makeCredential(
            spaceID: spaceID,
            protectionSpace: scope,
            username: "member",
            password: "old-secret"
        )
        var prompts: [BrowserHTTPAuthenticationPrompt] = []
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            loadCredential: { _ in stored },
            saveCredential: { saves.append($0) }
        )

        _ = await session.response(
            to: makeChallenge(protectionSpace: protectionSpace)
        ) { _ in
            XCTFail("The first challenge should reuse the stored credential")
            return nil
        }
        let retry = await session.response(
            to: makeChallenge(
                protectionSpace: protectionSpace,
                proposedUsername: "member",
                previousFailureCount: 1
            )
        ) { prompt in
            prompts.append(prompt)
            return BrowserHTTPAuthenticationPromptResponse(
                username: "member",
                password: "new-secret",
                shouldSave: true
            )
        }

        XCTAssertEqual(retry.credential?.password, "new-secret")
        XCTAssertEqual(prompts.first?.suggestedUsername, "member")
        XCTAssertEqual(prompts.first?.allowsSaving, true)
        XCTAssertTrue(saves.isEmpty)

        await session.authenticationSucceeded()

        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves.first?.replacing, stored.descriptor)
        XCTAssertEqual(saves.first?.password, "new-secret")
    }

    func testPlainHTTPCanSignInOnceButCannotLoadOrSaveACredential() async throws {
        let spaceID = UUID()
        let protectionSpace = makeProtectionSpace(protocol: "http", port: 80)
        var loadCount = 0
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            loadCredential: { _ in
                loadCount += 1
                return nil
            },
            saveCredential: { saves.append($0) }
        )

        let resolution = await session.response(
            to: makeChallenge(protectionSpace: protectionSpace)
        ) { prompt in
            XCTAssertFalse(prompt.allowsSaving)
            return BrowserHTTPAuthenticationPromptResponse(
                username: "member",
                password: "one-time-secret",
                shouldSave: true
            )
        }
        await session.authenticationSucceeded()

        XCTAssertEqual(resolution.disposition, .useCredential)
        XCTAssertEqual(resolution.credential?.password, "one-time-secret")
        XCTAssertEqual(loadCount, 0)
        XCTAssertTrue(saves.isEmpty)
    }

    func testPrivateBrowsingHTTPSAuthenticationIsAlwaysOneTimeOnly() async throws {
        let spaceID = UUID()
        let protectionSpace = makeProtectionSpace()
        var loadCount = 0
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        var prompts: [BrowserHTTPAuthenticationPrompt] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            allowsCredentialSaving: false,
            loadCredential: { _ in
                loadCount += 1
                return nil
            },
            saveCredential: { saves.append($0) }
        )

        let resolution = await session.response(
            to: makeChallenge(protectionSpace: protectionSpace)
        ) { prompt in
            prompts.append(prompt)
            return BrowserHTTPAuthenticationPromptResponse(
                username: "private-member",
                password: "one-time-secret",
                shouldSave: true
            )
        }
        await session.authenticationSucceeded()

        XCTAssertEqual(resolution.disposition, .useCredential)
        XCTAssertEqual(resolution.credential?.password, "one-time-secret")
        XCTAssertEqual(prompts.first?.allowsSaving, false)
        XCTAssertEqual(loadCount, 0)
        XCTAssertTrue(saves.isEmpty)
    }

    func testAuthenticationFailureClearsAPendingSaveRequest() async {
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: UUID(),
            saveCredential: { saves.append($0) }
        )

        _ = await session.response(
            to: makeChallenge(protectionSpace: makeProtectionSpace())
        ) { _ in
            BrowserHTTPAuthenticationPromptResponse(
                username: "member",
                password: "not-accepted",
                shouldSave: true
            )
        }
        session.authenticationFailed()
        await session.authenticationSucceeded()

        XCTAssertTrue(saves.isEmpty)
    }

    func testReplacementRequiresTheRejectedStoredUsernameToMatch() async throws {
        let spaceID = UUID()
        let protectionSpace = makeProtectionSpace()
        let typedProtectionSpace = try XCTUnwrap(
            BrowserHTTPAuthenticationProtectionSpace(protectionSpace)
        )
        let stored = makeCredential(
            spaceID: spaceID,
            protectionSpace: typedProtectionSpace,
            username: "stored-member",
            password: "old-secret"
        )
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            loadCredential: { _ in stored },
            saveCredential: { saves.append($0) }
        )

        _ = await session.response(to: makeChallenge(protectionSpace: protectionSpace)) { _ in
            XCTFail("The stored credential should be attempted before prompting")
            return nil
        }
        _ = await session.response(
            to: makeChallenge(
                protectionSpace: protectionSpace,
                proposedUsername: "server-proposed",
                previousFailureCount: 1
            )
        ) { prompt in
            XCTAssertEqual(prompt.suggestedUsername, "server-proposed")
            return BrowserHTTPAuthenticationPromptResponse(
                username: "different-member",
                password: "new-secret",
                shouldSave: true
            )
        }
        await session.authenticationSucceeded()

        XCTAssertEqual(saves.count, 1)
        XCTAssertNil(saves.first?.replacing)
    }

    private func makeProtectionSpace(
        protocol scheme: String = "https",
        port: Int = 443
    ) -> URLProtectionSpace {
        URLProtectionSpace(
            host: "accounts.crest.test",
            port: port,
            protocol: scheme,
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
    }

    private func makeChallenge(
        protectionSpace: URLProtectionSpace,
        proposedUsername: String? = nil,
        previousFailureCount: Int = 0
    ) -> URLAuthenticationChallenge {
        URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: proposedUsername.map {
                URLCredential(user: $0, password: "", persistence: .none)
            },
            previousFailureCount: previousFailureCount,
            failureResponse: nil,
            error: nil,
            sender: AuthenticationChallengeSenderStub()
        )
    }

    private func makeCredential(
        spaceID: UUID,
        protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        username: String,
        password: String
    ) -> BrowserCredential {
        BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: spaceID,
                origin: protectionSpace.origin,
                scope: protectionSpace.credentialScope,
                username: username,
                createdAt: Date(timeIntervalSince1970: 1_000)
            ),
            password: password
        )
    }
}

private final class AuthenticationChallengeSenderStub: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}
