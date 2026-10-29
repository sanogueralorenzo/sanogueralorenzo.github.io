import Foundation

enum BrowserWebAddress {
    static func host(_ spelling: String?) -> String? {
        spelling.flatMap(URL.init(string:))?.host().flatMap { $0.isEmpty ? nil : $0 }
    }
    static func place(_ spelling: String?) -> String? {
        guard let spelling, let url = URL(string: spelling)?.standardized,
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = parts.host?.lowercased(), !host.isEmpty
        else { return nil }
        let port = parts.port.flatMap { $0 == (scheme == "https" ? 443 : 80) ? nil : ":\($0)" } ?? ""
        let path = parts.percentEncodedPath == "/" ? "" : parts.percentEncodedPath
        return withoutWww(host) + port + path + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
    }
    static func normalized(_ spelling: String?) -> String? {
        guard let spelling, let scheme = URL(string: spelling)?.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else { return nil }
        return String(spelling.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
    }
    static func withoutWww(_ host: String) -> String { host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
}
