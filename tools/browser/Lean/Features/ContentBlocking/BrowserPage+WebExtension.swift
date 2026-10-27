import WebKit

extension BrowserPage: WKWebExtensionTab {
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { contentBlocker }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    func url(for context: WKWebExtensionContext) -> URL? { webView.url }
    func title(for context: WKWebExtensionContext) -> String? { webView.title }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !webView.isLoading }
}
