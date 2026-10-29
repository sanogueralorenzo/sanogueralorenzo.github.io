import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserAuthenticationPolicyTests: XCTestCase {
    /// Foundation's challenge names map onto the native methods so that only
    /// Basic and Digest reach Crest's credential prompt.
    func testTrustAndClientCertificateChallengesRemainSystemOwned() {
        for method in [
            NSURLAuthenticationMethodServerTrust,
            NSURLAuthenticationMethodClientCertificate,
            NSURLAuthenticationMethodNTLM,
        ] {
            XCTAssertEqual(
                AuthenticationHandling.handling(
                    method: AuthenticationMethod(authenticationMethod: method),
                    isProxy: false,
                    previousFailureCount: 0
                ),
                .performDefaultHandling
            )
        }
        XCTAssertEqual(
            AuthenticationHandling.handling(
                method: AuthenticationMethod(authenticationMethod: NSURLAuthenticationMethodHTTPDigest),
                isProxy: false,
                previousFailureCount: 0
            ),
            .promptForCredentials
        )
    }

    func testHTTPSignInPromptsEachTimeAndNeverPersistsThePassword() async throws {
        for scheme in ["http", "https"] {
            let session = BrowserHTTPAuthenticationSession()
            let protection = URLProtectionSpace(
                host: "accounts.crest.test", port: scheme == "https" ? 443 : 80,
                protocol: scheme, realm: "Members", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
            let challenge = makeChallenge(protectionSpace: protection)
            var prompts = 0
            for _ in 0..<2 {
                let resolution = await session.response(to: challenge) { _ in
                    prompts += 1
                    return BrowserHTTPAuthenticationPromptResponse(username: "member", password: "temporary-secret")
                }
                XCTAssertEqual(resolution.disposition, .useCredential)
                XCTAssertEqual(resolution.credential?.user, "member")
                XCTAssertEqual(resolution.credential?.password, "temporary-secret")
                XCTAssertEqual(resolution.credential?.persistence, URLCredential.Persistence.none)
            }
            XCTAssertEqual(prompts, 2)
        }
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

}

private final class AuthenticationChallengeSenderStub: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}
