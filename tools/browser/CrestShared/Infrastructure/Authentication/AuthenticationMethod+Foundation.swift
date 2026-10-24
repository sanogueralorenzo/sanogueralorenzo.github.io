import Foundation

extension AuthenticationMethod {
    init(authenticationMethod: String) {
        switch authenticationMethod {
        case NSURLAuthenticationMethodHTTPBasic:
            self = .httpBasic
        case NSURLAuthenticationMethodHTTPDigest:
            self = .httpDigest
        default:
            self = .other
        }
    }
}
