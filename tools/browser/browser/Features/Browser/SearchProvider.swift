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
        if let url = URL(string: text), ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") {
            return url
        }
        if !text.contains(where: \.isWhitespace), text.contains(".") || text.hasPrefix("localhost") {
            return URL(string: (text.hasPrefix("localhost") ? "http://" : "https://") + text)
        }
        return searchURL(text)
    }

    func searchURL(_ text: String) -> URL? {
        let endpoint: String
        switch self {
        case .google: endpoint = "https://www.google.com/search"
        case .duckDuckGo: endpoint = "https://duckduckgo.com/"
        case .bing: endpoint = "https://www.bing.com/search"
        case .brave: endpoint = "https://search.brave.com/search"
        }
        var components = URLComponents(string: endpoint)
        components?.queryItems = [URLQueryItem(name: "q", value: text)]
        return components?.url
    }
}
