import Foundation

/// Permission origins normalize once, before equality, hashing or persistence.
struct SiteOrigin: Hashable, Sendable {
    static let maximumSchemeLength = 64
    static let maximumHostLength = 1024
    let scheme: String
    let host: String
    let port: Int

    var isValid: Bool {
        (1...Self.maximumSchemeLength).contains(scheme.utf16.count)
            && (1...Self.maximumHostLength).contains(host.utf16.count) && (-1...65535).contains(port)
    }
    var isSecureContext: Bool {
        isValid
            && WebScheme.named(scheme).map {
                $0.isSecure || ["localhost", "127.0.0.1", "::1"].contains(host)
            } == true
    }

    // MARK: - Variables

    /// The origin as a person reads it: the port only when it is not the
    /// scheme's default.
    var displayName: String {
        WebScheme.named(scheme)?.defaultPort == port ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
    }

    // MARK: - Initializers

    init(scheme: String, host: String, port: Int) {
        let scheme = scheme.lowercased()
        self.scheme = scheme
        self.host = host.lowercased()
        self.port = port > 0 ? port : WebScheme.named(scheme)?.defaultPort ?? port
    }

    /// The origin of a URL with a scheme and a host, or nil for one without,
    /// such as a file URL.
    init?(url: URL) {
        guard let scheme = url.scheme, let host = url.host(), !host.isEmpty else { return nil }
        self.init(scheme: scheme, host: host, port: url.port ?? 0)
    }
}

/// Persisted origins use the same normalization as newly constructed origins.
extension SiteOrigin: Codable {
    private enum CodingKeys: String, CodingKey {
        case scheme
        case host
        case port
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            scheme: try container.decode(String.self, forKey: .scheme),
            host: try container.decode(String.self, forKey: .host),
            port: try container.decode(Int.self, forKey: .port))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scheme, forKey: .scheme)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
    }
}
