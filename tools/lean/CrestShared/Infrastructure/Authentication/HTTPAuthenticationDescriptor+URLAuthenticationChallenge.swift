import Foundation

extension BrowserHTTPAuthenticationDescriptor {
    init(challenge: URLAuthenticationChallenge) {
        let protectionSpace = challenge.protectionSpace
        self.init(
            source: Self.sourceLabel(for: protectionSpace),
            realm: protectionSpace.realm,
            authenticationMethod: protectionSpace.authenticationMethod,
            isSecureTransport: WebScheme.named(protectionSpace.protocol?.lowercased())?.isSecure == true,
            previousFailureCount: challenge.previousFailureCount
        )
    }

    static func sourceLabel(for protectionSpace: URLProtectionSpace) -> String {
        AuthenticationSource.label(
            host: protectionSpace.host,
            port: protectionSpace.port,
            scheme: protectionSpace.protocol,
            emptyHostLabel: ProductIdentity.name
        )
    }
}
