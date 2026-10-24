import Foundation

/// The platform's canonical form of a credential origin: a lowercased HTTP(S)
/// scheme and host, and an explicit port. The core compares origins member by
/// member, so every origin is canonicalized here before it reaches the core or
/// the vault.
extension CredentialOrigin {
    // MARK: - Variables

    var isSecure: Bool { WebScheme.named(scheme)?.isSecure == true }

    // MARK: - Initializers

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let webScheme = WebScheme.named(components.scheme?.lowercased()),
            let rawHost = components.host,
            !rawHost.isEmpty
        else {
            return nil
        }

        let authorityHost =
            rawHost.contains(":") && !rawHost.hasPrefix("[")
            ? "[\(rawHost)]"
            : rawHost
        guard let canonicalizationURL = URL(string: "https://\(authorityHost)"),
            let canonicalHost = canonicalizationURL.host(percentEncoded: false)?.lowercased(),
            !canonicalHost.isEmpty
        else {
            return nil
        }

        let resolvedPort = components.port ?? webScheme.defaultPort
        guard (1...65_535).contains(resolvedPort) else { return nil }

        self.init(scheme: webScheme.name, host: canonicalHost, port: resolvedPort)
    }

    init?(securityProtocol rawProtocol: String, host rawHost: String, port rawPort: Int) {
        guard let webScheme = WebScheme.named(rawProtocol.lowercased()),
            !rawHost.isEmpty
        else {
            return nil
        }

        let resolvedPort = rawPort > 0 ? rawPort : webScheme.defaultPort
        guard (1...65_535).contains(resolvedPort) else { return nil }

        let renderedHost =
            rawHost.contains(":") && !rawHost.hasPrefix("[")
            ? "[\(rawHost)]"
            : rawHost
        let portSuffix =
            resolvedPort == webScheme.defaultPort
            ? ""
            : ":\(resolvedPort)"
        guard let url = URL(string: "\(webScheme.name)://\(renderedHost)\(portSuffix)") else {
            return nil
        }
        self.init(url: url)
    }

    // MARK: - Actions - Matching

    func matches(_ url: URL) -> Bool {
        CredentialOrigin(url: url) == self
    }
}

extension CredentialOrigin: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(scheme)
        hasher.combine(host)
        hasher.combine(port)
    }
}

extension CredentialOrigin: CustomStringConvertible {
    var description: String {
        let renderedHost = host.contains(":") ? "[\(host)]" : host
        return port == WebScheme.named(scheme)?.defaultPort
            ? "\(scheme)://\(renderedHost)"
            : "\(scheme)://\(renderedHost):\(port)"
    }
}

/// Stored credentials keep this spelling; decoding accepts only canonical data.
extension CredentialOrigin: Codable {
    private enum CodingKeys: String, CodingKey {
        case scheme
        case host
        case port
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedScheme = try container.decode(String.self, forKey: .scheme)
        let decodedHost = try container.decode(String.self, forKey: .host)
        let decodedPort = try container.decode(Int.self, forKey: .port)

        var components = URLComponents()
        components.scheme = decodedScheme
        components.host = decodedHost
        components.port =
            decodedPort == WebScheme.named(decodedScheme.lowercased())?.defaultPort
            ? nil
            : decodedPort
        guard let url = components.url,
            let canonical = CredentialOrigin(url: url),
            canonical.scheme == decodedScheme,
            canonical.host == decodedHost,
            canonical.port == decodedPort
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .host,
                in: container,
                debugDescription: "Credential origin is not canonical HTTP(S) data"
            )
        }
        self = canonical
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scheme, forKey: .scheme)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
    }
}
