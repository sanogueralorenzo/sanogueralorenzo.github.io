import Foundation

/// A web link shared to Crest from another app. The share extension hands it
/// to the app as a `crest://open` URL.
///
/// Any app can open that URL, so it carries the web link and nothing else,
/// and the app routes the link as it would any link another app opens: link
/// routes, Quick Windows and locked Spaces behave the same.
struct BrowserSharedLink: Equatable, Sendable {
    // MARK: - Static Variables

    private static let handOffScheme = "crest"
    private static let handOffHost = "open"
    private static let urlParameter = "url"
    private static let webSchemes: Set<String> = ["http", "https"]
    /// Characters a query value keeps unescaped, so `&`, `=` and `+` inside
    /// the shared link never split the hand-off's own parameter.
    private static let queryValueCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    // MARK: - Variables

    let url: URL

    /// The `crest://open` URL that hands this link to the app.
    var handOffURL: URL {
        var components = URLComponents()
        components.scheme = Self.handOffScheme
        components.host = Self.handOffHost
        components.percentEncodedQueryItems = [
            URLQueryItem(
                name: Self.urlParameter,
                value: url.absoluteString.addingPercentEncoding(withAllowedCharacters: Self.queryValueCharacters))
        ]
        guard let handOffURL = components.url else {
            preconditionFailure("A crest://open URL with an escaped link always forms.")
        }
        return handOffURL
    }

    // MARK: - Initializers

    /// A shared web link, or nil for anything but an `http` or `https` URL
    /// with a host.
    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), Self.webSchemes.contains(scheme),
            url.host(percentEncoded: false)?.isEmpty == false
        else { return nil }
        self.url = url
    }

    /// The link a `crest://open` URL hands over, or nil for any other URL,
    /// for a link given more than once, and for a link that is not a web
    /// link.
    init?(handOffURL: URL) {
        guard handOffURL.scheme?.lowercased() == Self.handOffScheme,
            handOffURL.host(percentEncoded: false)?.lowercased() == Self.handOffHost,
            handOffURL.path().isEmpty || handOffURL.path() == "/",
            let parameters = URLComponents(url: handOffURL, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        let links = parameters.filter { $0.name == Self.urlParameter }
        guard links.count == 1, let value = links[0].value, let url = URL(string: value) else { return nil }
        self.init(url: url)
    }

    // MARK: - Actions - Reading shared text

    /// The first web link in text another app shared, such as a note or a
    /// message, or nil when it holds none.
    static func firstWebLink(in text: String) -> BrowserSharedLink? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).lazy
            .compactMap(\.url)
            .compactMap { BrowserSharedLink(url: $0) }
            .first
    }
}
