/// The page's main frame reported a change to its media session.
struct BrowserPageMediaSessionChanged: BrowserPageEngineEvent {
    // MARK: - Variables

    let event: BrowserMediaSessionPageEvent

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.mediaSessionCoordinator?.receive(event, isMainFrame: true)
    }
}
