import Foundation
import WebKit

/// A server's request for a user name and password, answered through the core.
extension BrowserPlatformPage {
    /// Answers `challenge` for a load of this page: a certificate the person
    /// trusted for this profile is accepted, any other certificate takes
    /// WebKit's own handling and is kept for the page to explain, and a
    /// sign-in goes through `answerSignIn`.
    func answerChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let identity = BrowserServerTrustIdentity.challengeIdentity(for: challenge) {
            if serverTrustOverrides.isApproved(identity, for: profileID),
                let trust = challenge.protectionSpace.serverTrust
            {
                pendingServerTrustIdentity = nil
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                pendingServerTrustIdentity = identity
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }
        answerSignIn(challenge, from: webKitEnginePage, completionHandler: completionHandler)
    }

    /// Answers `challenge` for a load of this page. A challenge the core's
    /// rules prompt for goes to the core as a question about `webKitPage`,
    /// which the page's Space's saved sign-in or the person answers; one the
    /// rules leave to the system, or cancel, never reaches it.
    func answerSignIn(
        _ challenge: URLAuthenticationChallenge, from webKitPage: WebKitEnginePage?,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        BrowserAuthenticationChallenge(challenge).handling.respond(
            on: WebKitSignInResponder(
                challenge: challenge, page: webKitPage, session: httpAuthenticationSession,
                completionHandler: completionHandler))
    }
}
