import Foundation

enum SearchProvider: String, Codable, CaseIterable, Identifiable {
    case google = "Google"
    case duckDuckGo = "DuckDuckGo"
    case bing = "Bing"
    case brave = "Brave"

    var id: String { rawValue }

    func suggestionsURL(for query: String) -> URL? {
        let endpoint: String
        var parameters: [URLQueryItem] = []
        switch self {
        case .google:
            endpoint = "https://www.google.com/complete/search"
            parameters = [URLQueryItem(name: "client", value: "chrome"), URLQueryItem(name: "q", value: query)]
        case .duckDuckGo:
            endpoint = "https://duckduckgo.com/ac/"
            parameters = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "list")]
        case .bing:
            endpoint = "https://www.bing.com/osjson.aspx"
            parameters = [URLQueryItem(name: "query", value: query)]
        case .brave:
            endpoint = "https://search.brave.com/api/suggest"
            parameters = [URLQueryItem(name: "q", value: query)]
        }
        var components = URLComponents(string: endpoint)
        components?.queryItems = parameters
        return components?.url
    }

    func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return Self.explicitAddress(text) ?? searchURL(text)
    }

    static func explicitAddress(_ text: String) -> URL? {
        if let url = URL(string: text), ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }
        if !text.contains(where: \.isWhitespace), text.contains(".") || text.hasPrefix("localhost") {
            return URL(string: (text.hasPrefix("localhost") ? "http://" : "https://") + text)
        }
        return nil
    }

    func searchURL(_ text: String) -> URL? {
        makeSearchURL(endpoint: searchEndpoint, parameter: "q", text: text)
    }

    fileprivate var searchEndpoint: String {
        switch self {
        case .google: "https://www.google.com/search"
        case .duckDuckGo: "https://duckduckgo.com/"
        case .bing: "https://www.bing.com/search"
        case .brave: "https://search.brave.com/search"
        }
    }
}

struct BrowserSiteSearchShortcut {
    let name: String
    private let endpoint: String
    private var queryParameter = "q"

    private static let all = [
        Self(name: "YouTube", endpoint: "https://www.youtube.com/results", queryParameter: "search_query"),
        Self(name: "Wikipedia", endpoint: "https://en.wikipedia.org/wiki/Special:Search?fulltext=1", queryParameter: "search"),
        Self(name: "Reddit", endpoint: "https://www.reddit.com/search/"),
        Self(name: "GitHub", endpoint: "https://github.com/search"),
        Self(name: "Amazon", endpoint: "https://www.amazon.com/s", queryParameter: "k"),
    ] + SearchProvider.allCases.map { Self(name: $0.rawValue, endpoint: $0.searchEndpoint) }

    static func matching(_ text: String) -> Self? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = all.first(where: { $0.name.caseInsensitiveCompare(text) == .orderedSame }) { return match }
        guard let address = SearchProvider.explicitAddress(text),
            let components = URLComponents(url: address, resolvingAgainstBaseURL: false),
            components.scheme == "http" || components.scheme == "https",
            components.path.isEmpty || components.path == "/",
            components.query == nil, components.fragment == nil,
            components.user == nil, components.password == nil, components.port == nil,
            let host = BrowserAddressMatch.hostName(address), host.contains(".")
        else { return nil }
        return all.first {
            guard let siteHost = BrowserAddressMatch.hostName(URL(string: $0.endpoint)) else { return false }
            return siteHost == host || siteHost.hasSuffix("." + host)
        }
    }

    func searchURL(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return makeSearchURL(endpoint: endpoint, parameter: queryParameter, text: text)
    }
}

private func makeSearchURL(endpoint: String, parameter: String, text: String) -> URL? {
    guard var components = URLComponents(string: endpoint) else { return nil }
    components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: parameter, value: text)]
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return components.url
}
