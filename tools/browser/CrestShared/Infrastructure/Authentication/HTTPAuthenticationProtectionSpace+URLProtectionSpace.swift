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

        var components = URLComponents()
        components.scheme = scheme
        components.host = protectionSpace.host
        components.port = protectionSpace.port
        guard let url = components.url,
            let origin = CredentialOrigin(url: url)
        else {
            return nil
        }

        self.init(origin: origin, credentialScope: credentialScope)
    }
}
