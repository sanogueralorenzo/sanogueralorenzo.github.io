/// The engine's back-forward list changed.
struct BrowserPageHistoryChanged: BrowserPageEngineEvent {
    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.refreshNavigationState()
    }
}
