import Foundation

/// How the platform makes and reads the core's `SiteOrigin`. An origin is
/// normalized as it is made, the way the core's constructor makes one: the
/// scheme and host are lowercased, and a web scheme's missing port (0 or less)
/// becomes the scheme's default, while any other scheme keeps the port it was
/// given. Two spellings of one origin are therefore equal and hash alike under
/// the generated `Hashable`, which reads the stored fields.
///
/// The codec alone makes origins through the wire initializer, from values the
/// core already normalized; the generator refuses any other caller.
extension SiteOrigin {
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

/// The spelling the core's JSON policy requests read and its answers write. A
/// decoded origin is normalized like any other.
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
