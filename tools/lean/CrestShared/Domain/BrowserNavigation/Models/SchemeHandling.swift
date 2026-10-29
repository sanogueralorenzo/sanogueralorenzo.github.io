import Foundation

enum ExternalSchemeDisposition: CaseIterable, CoreNamedValue, Sendable {
    case engine, blocked, handOff
    var name: String {
        switch self {
        case .engine: "engine"
        case .blocked: "blocked"
        case .handOff: "handOff"
        }
    }
    static func named(_ name: String?) -> Self? { allCases.first { $0.name == name } }
}

enum SchemeHandling {
    static func disposition(for url: URL?, isAppInitiated: Bool = false) -> ExternalSchemeDisposition {
        disposition(scheme: url?.scheme.nonEmpty, isAppInitiated: isAppInitiated)
    }

    static func disposition(scheme: String?, isAppInitiated: Bool) -> ExternalSchemeDisposition {
        guard let scheme, !scheme.isEmpty else { return .engine }
        guard scheme.utf16.count <= 256 else { return .blocked }
        switch scheme.lowercased() {
        case "http", "https", "about", "blob", "chrome-extension", "crest-extension", "data", "webkit-extension":
            return .engine
        case "javascript": return .blocked
        case "file": return isAppInitiated ? .engine : .blocked
        default: return .handOff
        }
    }
}

enum ExternalLocalDocument {
    static func accepts(_ url: URL) -> Bool {
        accepts(
            isFile: url.isFileURL, hasUser: url.user() != nil, hasPath: !url.path().isEmpty,
            host: url.host(percentEncoded: false).nonEmpty)
    }

    static func accepts(isFile: Bool, hasUser: Bool, hasPath: Bool, host: String?) -> Bool {
        guard isFile, !hasUser, hasPath, host.map({ $0.utf16.count <= 1024 }) ?? true else { return false }
        return host?.isEmpty != false || host?.lowercased() == "localhost"
    }
}
