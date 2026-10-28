import Foundation

extension AuthenticationQuestion {
    /// The question a server's challenge for an HTTP user name and password
    /// asks, or nil for any other challenge.
    init?(_ challenge: URLAuthenticationChallenge) {
        let space = challenge.protectionSpace
        let scheme: AuthenticationScheme
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodHTTPBasic: scheme = .basic
        case NSURLAuthenticationMethodHTTPDigest: scheme = .digest
        default: return nil
        }
        let address =
            challenge.failureResponse?.url?.absoluteString
            ?? "\(space.protocol ?? "https")://\(space.host):\(space.port)/"
        self.init(
            url: address, host: space.host, port: space.port, realm: space.realm, scheme: scheme,
            isProxy: space.isProxy(), previousFailures: challenge.previousFailureCount)
    }
}
