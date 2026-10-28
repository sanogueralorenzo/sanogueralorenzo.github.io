/// The page left the screen, as switching to another tab takes it off.
struct BrowserPageLeftScreen: BrowserPageEngineEvent {
    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        // A bar the person hid shows again once they come back.
        page.restoreMinimizedInfoBars()
    }
}
