import UIKit

@MainActor
enum BrowserPageLinkClipboard {
    @discardableResult
    static func copy(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        UIPasteboard.general.string = urls.map(\.absoluteString).joined(separator: "\n")
        return true
    }

    @discardableResult
    static func copy(_ url: URL?) -> Bool {
        guard let url else { return false }
        UIPasteboard.general.url = url
        return true
    }
}
