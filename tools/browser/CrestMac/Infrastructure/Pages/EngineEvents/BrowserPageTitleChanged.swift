/// The document's title changed.
struct BrowserPageTitleChanged: BrowserPageEngineEvent {
    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.mediaSessionCoordinator?.ownerTitleDidChange()
        page.refreshNavigationState()
    }
}
