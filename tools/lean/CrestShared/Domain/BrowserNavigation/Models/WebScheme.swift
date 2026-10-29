/// The schemes whose URLs identify web pages and permission origins.
enum WebScheme: String, Sendable {
    case http, https

    var defaultPort: Int { self == .http ? 80 : 443 }
    var isSecure: Bool { self == .https }
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }
}
