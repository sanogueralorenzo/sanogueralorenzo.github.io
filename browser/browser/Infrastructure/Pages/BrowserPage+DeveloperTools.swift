import WebKit

extension BrowserPage {
    func showDeveloperTools() {
        let selector = NSSelectorFromString("_inspector")
        guard webView.responds(to: selector),
            let inspector = webView.perform(selector)?.takeUnretainedValue() as? NSObject,
            inspector.responds(to: NSSelectorFromString("show"))
        else {
            owner?.showNotice("Use Inspect Element in the page's context menu.")
            return
        }
        inspector.perform(NSSelectorFromString("show"))
    }
}
