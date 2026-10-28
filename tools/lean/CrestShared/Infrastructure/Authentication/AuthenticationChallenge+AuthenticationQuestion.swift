import Foundation

extension BrowserAuthenticationChallenge {
    /// The challenge the core's question about a server's sign-in describes,
    /// whichever engine asked it; nil when its address names no origin.
    init?(_ question: AuthenticationQuestion) {
        guard let url = URL(string: question.url), url.host != nil
        else { return nil }
        let realm = question.realm.flatMap { $0.isEmpty ? nil : $0 }
        let method: AuthenticationMethod
        // The scheme as the challenge's descriptor names it.
        let schemeName: String
        switch question.scheme {
        case .basic:
            method = .httpBasic
            schemeName = "basic"
        case .digest:
            method = .httpDigest
            schemeName = "digest"
        }
        let previousFailures = question.previousFailures
        self.init(
            authenticationMethod: method,
            isProxy: question.isProxy,
            previousFailureCount: previousFailures,
            descriptor: BrowserHTTPAuthenticationDescriptor(
                source: AuthenticationSource.label(
                    host: question.host, port: question.port, scheme: url.scheme, emptyHostLabel: ProductIdentity.name),
                realm: realm,
                authenticationMethod: schemeName,
                isSecureTransport: url.scheme?.lowercased() == "https",
                previousFailureCount: previousFailures),
            proposedUsername: nil)
    }
}
