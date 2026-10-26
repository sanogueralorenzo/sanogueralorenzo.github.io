import Foundation
import Security

extension PageSecurity {
    /// WebKit's judgment of a page. WebKit reports only whether every resource
    /// arrived securely, so a certificate error is recognized from the trust it
    /// kept: an evaluation that failed, or a certificate the person chose to
    /// trust for this profile, which Crest records only for a failing one.
    init(
        webKitURL url: URL?,
        hasOnlySecureContent: Bool,
        serverTrust: SecTrust?,
        isApprovedOverride: (BrowserServerTrustIdentity) -> Bool
    ) {
        switch url?.scheme?.lowercased() {
        case "https":
            if let url, let serverTrust,
                Self.isCertificateError(serverTrust, url: url, isApprovedOverride: isApprovedOverride)
            {
                self = .certificateError
            } else {
                self = hasOnlySecureContent ? .secure : .mixedContent
            }
        case "http":
            self = .insecure
        default:
            self = .none
        }
    }

    // MARK: - Actions - Trust

    private static func isCertificateError(
        _ trust: SecTrust,
        url: URL,
        isApprovedOverride: (BrowserServerTrustIdentity) -> Bool
    ) -> Bool {
        // The result WebKit's own evaluation left on the trust, read without
        // evaluating it again on the main thread.
        var result = SecTrustResultType.invalid
        if SecTrustGetTrustResult(trust, &result) == errSecSuccess {
            switch result {
            case .deny, .recoverableTrustFailure, .fatalTrustFailure, .otherError: return true
            default: break
            }
        }
        guard let host = url.host(),
            let identity = BrowserServerTrustIdentity.identity(for: trust, host: host, port: url.port ?? 443)
        else { return false }
        return isApprovedOverride(identity)
    }
}
