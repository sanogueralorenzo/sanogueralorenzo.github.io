import AppKit

@MainActor
enum BrowserPageLinkClipboard {
    @discardableResult
    static func copy(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
    }

    @discardableResult
    static func copy(_ url: URL?) -> Bool {
        guard let url else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(url.absoluteString, forType: .string)
    }
}
