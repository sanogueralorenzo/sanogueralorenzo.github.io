import Foundation

/// Text only. Keeping URL escapes intact avoids giving directional controls or
/// encoded delimiters a different visual meaning. This value is never opened.
struct BrowserLinkHoverDestination: Equatable {
    let text: String

    init?(resolvedURL: String) {
        guard resolvedURL.utf8.count <= 8_192,
            let url = URL(string: resolvedURL),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme != nil
        else { return nil }
        components.user = nil
        components.password = nil
        guard let value = components.url?.absoluteString else { return nil }
        text = value
    }
}
