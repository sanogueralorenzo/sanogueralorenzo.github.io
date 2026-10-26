import CryptoKit
import Foundation
import Security

extension BrowserServerTrustIdentity {
    static func challengeIdentity(
        for challenge: URLAuthenticationChallenge
    ) -> BrowserServerTrustIdentity? {
        let protectionSpace = challenge.protectionSpace
        guard
            protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodServerTrust,
            let trust = protectionSpace.serverTrust
        else { return nil }
        return identity(for: trust, host: protectionSpace.host, port: protectionSpace.port)
    }

    /// The identity of `trust`'s leaf certificate served for `host` and `port`;
    /// a port of zero or less means HTTPS's default.
    static func identity(for trust: SecTrust, host: String, port: Int) -> BrowserServerTrustIdentity? {
        guard let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        else { return nil }
        let certificateData = SecCertificateCopyData(certificate) as Data
        let fingerprint = SHA256.hash(data: certificateData)
            .map { String(format: "%02X", $0) }
            .joined()
        return BrowserServerTrustIdentity(
            host: host,
            port: port > 0 ? port : 443,
            certificateSHA256: fingerprint
        )
    }
}
