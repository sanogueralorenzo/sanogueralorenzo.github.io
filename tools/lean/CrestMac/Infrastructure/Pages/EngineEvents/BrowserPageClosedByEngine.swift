/// The engine closed the page on its own authority, as an extension's
/// `chrome.tabs.remove` does. The core already closed what owned it.
struct BrowserPageClosedByEngine: BrowserPageEngineEvent {
    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        Task { @MainActor [weak page] in
            guard let page else { return }
            page.host?.releaseEngineClosedPage(page)
        }
    }
}
