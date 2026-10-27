import Foundation

struct BrowserURLs {
    static func same(_ first: URL?, _ second: URL?) -> Bool {
        guard let first, let second else { return first == nil && second == nil }
        func normalized(_ url: URL) -> String {
            guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url.absoluteString }
            parts.scheme = parts.scheme?.lowercased()
            parts.host = parts.host?.lowercased()
            if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) {
                parts.port = nil
            }
            if parts.path.isEmpty { parts.path = "/" }
            return parts.string ?? url.absoluteString
        }
        return normalized(first) == normalized(second)
    }
}
