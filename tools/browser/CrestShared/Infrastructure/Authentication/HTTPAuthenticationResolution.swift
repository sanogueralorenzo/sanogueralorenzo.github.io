import Foundation

struct BrowserHTTPAuthenticationResolution {
    let disposition: URLSession.AuthChallengeDisposition
    let credential: URLCredential?

    init(
        disposition: URLSession.AuthChallengeDisposition,
        credential: URLCredential?
    ) {
        self.disposition = disposition
        self.credential = credential
    }

    init(_ decision: BrowserHTTPAuthenticationDecision) {
        switch decision {
        case .performDefaultHandling:
            self.init(disposition: .performDefaultHandling, credential: nil)
        case .cancel:
            self.init(disposition: .cancelAuthenticationChallenge, credential: nil)
        case .useCredential(let username, let password):
            self.init(
                disposition: .useCredential,
                credential: URLCredential(
                    user: username,
                    password: password,
                    persistence: .none
                )
            )
        }
    }
}
