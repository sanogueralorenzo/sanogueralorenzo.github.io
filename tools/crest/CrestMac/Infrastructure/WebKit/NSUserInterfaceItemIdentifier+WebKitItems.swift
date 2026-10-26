import AppKit

extension NSUserInterfaceItemIdentifier {
    // MARK: - Static Variables

    /// WebKit's own context menu items, found by identifier rather than by
    /// their localized titles.
    static let webKitSearchWeb = Self("WKMenuItemIdentifierSearchWeb")
    static let webKitOpenLinkInNewWindow = Self("WKMenuItemIdentifierOpenLinkInNewWindow")
    static let webKitPaste = Self("WKMenuItemIdentifierPaste")
    static let webKitDownloadImage = Self("WKMenuItemIdentifierDownloadImage")
}
