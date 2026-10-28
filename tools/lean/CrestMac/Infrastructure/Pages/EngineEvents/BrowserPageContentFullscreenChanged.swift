/// The document entered or left full screen.
struct BrowserPageContentFullscreenChanged: BrowserPageEngineEvent {
    // MARK: - Variables

    let isActive: Bool

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.isContentFullscreen = isActive
    }
}
