import Foundation

struct BrowserServerTrustIdentity: Hashable, Sendable {
    let host: String
    let port: Int
    let certificateSHA256: String

    init(host: String, port: Int, certificateSHA256: String) {
        self.host = host.lowercased()
        self.port = port
        self.certificateSHA256 = certificateSHA256.uppercased()
    }
}
