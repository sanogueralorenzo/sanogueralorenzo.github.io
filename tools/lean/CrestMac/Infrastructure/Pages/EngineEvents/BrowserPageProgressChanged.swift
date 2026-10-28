/// How far the engine has loaded the page, from 0 to 1.
struct BrowserPageProgressChanged: BrowserPageEngineEvent {
    // MARK: - Variables

    let progress: Double

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.estimatedProgress = progress
    }
}
