import Foundation

extension BrowserHTTPAuthenticationProtectionSpace {
    init?(_ protectionSpace: URLProtectionSpace) {
        guard !protectionSpace.isProxy(),
            let scheme = protectionSpace.protocol?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return nil
        }

        let credentialScope: BrowserCredentialScope
        switch protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodHTTPBasic:
            credentialScope = .httpBasic(realm: protectionSpace.realm)
        case NSURLAuthenticationMethodHTTPDigest:
            credentialScope = .httpDigest(realm: protectionSpace.realm)
        default:
            return nil
        }

        guard
            let origin = CredentialOrigin(
                securityProtocol: scheme,
                host: protectionSpace.host,
                port: protectionSpace.port
            )
        else {
            return nil
        }

        self.init(origin: origin, credentialScope: credentialScope)
    }
}
