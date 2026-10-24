import Foundation
import WebKit

/// A server's request for a user name and password during a WebKit load or
/// download. A challenge the core's rules prompt for goes to the core as a
/// question about `page`, which the page's Space's saved sign-in or the person
/// answers; one the rules leave to the system, or cancel, never reaches it.
@MainActor
struct WebKitSignInResponder: AuthenticationResponder {
    // MARK: - Variables

    let challenge: URLAuthenticationChallenge
    let page: WebKitEnginePage?

    /// The sign-in session of the page whose load was challenged, which
    /// forgets its attempt when the challenge is cancelled. A download has
    /// none.
    let session: BrowserHTTPAuthenticationSession?

    let completionHandler: @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void

    // MARK: - Actions - Answering

    func performDefaultHandling() {
        completionHandler(.performDefaultHandling, nil)
    }

    func cancelChallenge() {
        session?.authenticationFailed()
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    func promptForCredentials() {
        guard let page, let question = AuthenticationQuestion(challenge) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        page.ask(question) { credential in
            guard let credential else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(
                .useCredential,
                URLCredential(user: credential.username, password: credential.password, persistence: .none))
        }
    }
}
