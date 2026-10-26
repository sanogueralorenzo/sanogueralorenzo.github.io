import Foundation

/// Native window metadata shares the address bar's host formatting, but never
/// falls back to credentials, a local file path, or a URL's query and fragment.
@MainActor
enum BrowserWindowTitle {
    /// The title of a window showing `tab`, drawing on its live page when it has one.
    static func resolve(tab: TabStateModel, page: BrowserPage?) -> String {
        if tab.surface == .startPage { return String(localized: "Start Page") }
        if tab.nativeView != nil { return tab.shownTitle }
        if let title = BrowserShownTitle.resolve(tab.customTitle) { return title }
        return resolve(page: page, storedTitle: tab.title, url: tab.address)
    }

    static func resolve(
        page: BrowserPage?,
        storedTitle: String? = nil,
        url: URL?,
        fallback: String = ProductIdentity.name
    ) -> String {
        guard let page else {
            return resolve(title: storedTitle, url: url, fallback: fallback)
        }
        let title =
            page.live.pendingNavigationURL == nil && page.live.failure == nil
            ? page.live.title : nil
        return resolve(title: title, url: page.live.displayURL ?? url, fallback: fallback)
    }

    private static func resolve(title: String?, url: URL?, fallback: String) -> String {
        if let title = BrowserShownTitle.resolve(title) { return title }
        guard let url, let host = url.host(), !host.isEmpty else { return fallback }
        return BrowserAddressPresentation(url.absoluteString).domain
    }
}
