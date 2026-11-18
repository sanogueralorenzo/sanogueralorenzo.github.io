import Foundation

struct BrowserSiteSearch: Codable, Equatable, Sendable {
    static let maximumCount = 128
    private static let searchTerms = "{searchTerms}"
    private static let marker = "browser-search-term-placeholder"
    private static let termCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    let origin: String
    let name: String
    private let template: String

    init?(name: String, template: String, origin: String) {
        guard template.utf8.count <= 4096, !template.contains(Self.marker),
            template.components(separatedBy: Self.searchTerms).count == 2,
            var parts = URLComponents(string: template.replacingOccurrences(of: Self.searchTerms, with: Self.marker)),
            let url = parts.url, Self.origin(of: url) == origin,
            parts.user == nil, parts.password == nil
        else { return nil }

        if let items = parts.queryItems {
            parts.queryItems = items.filter {
                $0.value?.range(of: #"^\{[a-zA-Z0-9_:.-]+\?\}$"#, options: .regularExpression) == nil
            }
        }
        guard parts.path.contains(Self.marker) || parts.queryItems?.contains(where: { $0.value?.contains(Self.marker) == true }) == true,
            !parts.path.contains("{"), parts.fragment?.contains("{") != true,
            parts.queryItems?.contains(where: { $0.name.contains("{") || $0.value?.contains("{") == true }) != true,
            let normalized = parts.url, normalized.absoluteString.components(separatedBy: Self.marker).count == 2
        else { return nil }

        self.origin = origin
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        self.template = normalized.absoluteString.replacingOccurrences(of: Self.marker, with: Self.searchTerms)
        guard !self.name.isEmpty else { return nil }
    }

    func url(for input: String) -> URL? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, let encoded = input.addingPercentEncoding(withAllowedCharacters: Self.termCharacters),
            let url = URL(string: template.replacingOccurrences(of: Self.searchTerms, with: encoded)),
            Self.origin(of: url) == origin
        else { return nil }
        return url
    }

    static func origin(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host?.lowercased(), !host.isEmpty,
            url.user == nil, url.password == nil
        else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        if let port = url.port, port != (scheme == "https" ? 443 : 80) { parts.port = port }
        return parts.string
    }

    static func fromForm(action: URL, field: String, submittedURL: URL) -> Self? {
        guard let origin = origin(of: action), origin == Self.origin(of: submittedURL),
            var parts = URLComponents(url: submittedURL, resolvingAgainstBaseURL: false),
            parts.path == URLComponents(url: action, resolvingAgainstBaseURL: false)?.path,
            let query = parts.queryItems, query.count == 1, query[0].name == field,
            let value = query[0].value, !value.isEmpty, let host = parts.host
        else { return nil }
        parts.queryItems = [URLQueryItem(name: field, value: Self.marker)]
        parts.fragment = nil
        guard let template = parts.url?.absoluteString.replacingOccurrences(of: Self.marker, with: Self.searchTerms) else {
            return nil
        }
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return Self(name: name, template: template, origin: origin)
    }
}

final class BrowserOpenSearchDescription: NSObject, XMLParserDelegate {
    private var depth = 0
    private var validRoot = false
    private var name = ""
    private var readingName = false
    private var templates: [String] = []

    static func search(in source: String, origin: String) -> BrowserSiteSearch? {
        guard source.utf8.count <= 65_536, !source.contains("<!DOCTYPE") else { return nil }
        let parser = XMLParser(data: Data(source.utf8))
        let description = Self()
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = description
        guard parser.parse(), description.validRoot else { return nil }
        return description.templates.lazy.compactMap {
            BrowserSiteSearch(name: description.name, template: $0, origin: origin)
        }.first
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String]
    ) {
        depth += 1
        if depth == 1 { validRoot = elementName == "OpenSearchDescription" }
        guard depth == 2 else { return }
        if elementName == "ShortName" {
            readingName = true
        } else if elementName == "Url", attributes["type"] == "text/html",
            (attributes["method"] ?? "GET").uppercased() == "GET",
            (attributes["rel"] ?? "results").split(separator: " ").contains("results"),
            let template = attributes["template"]
        {
            templates.append(template)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if readingName { name.append(string) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if depth == 2 && elementName == "ShortName" { readingName = false }
        depth -= 1
    }
}
