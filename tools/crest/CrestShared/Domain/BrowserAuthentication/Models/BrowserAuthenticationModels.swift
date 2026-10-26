struct BrowserAuthenticationChallenge: Equatable, Sendable {
    let authenticationMethod: AuthenticationMethod
    let isProxy: Bool
    let previousFailureCount: Int
    let descriptor: BrowserHTTPAuthenticationDescriptor
    let proposedUsername: String?
}

enum BrowserHTTPAuthenticationDecision: Sendable {
    case performDefaultHandling
    case cancel
    case useCredential(username: String, password: String)

    /// The credential the decision answers a server with, if any.
    var credential: AuthenticationCredential? {
        switch self {
        case .useCredential(let username, let password):
            AuthenticationCredential(username: username, password: password)
        case .cancel, .performDefaultHandling: nil
        }
    }
}

struct BrowserHTTPAuthenticationDescriptor: Equatable, Sendable {
    let source: String
    let realm: String?
    let authenticationMethod: String
    let isSecureTransport: Bool
    let previousFailureCount: Int
}

struct BrowserHTTPAuthenticationPrompt: Equatable, Sendable {
    let descriptor: BrowserHTTPAuthenticationDescriptor
    let suggestedUsername: String?
}

struct BrowserHTTPAuthenticationPromptResponse:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let username: String
    let password: String

    var description: String {
        "BrowserHTTPAuthenticationPromptResponse(username: \(username), password: <redacted>)"
    }

    var debugDescription: String { description }
}
