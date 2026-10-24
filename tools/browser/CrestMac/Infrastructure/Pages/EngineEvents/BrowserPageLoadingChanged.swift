/// An engine that reports its own navigations says whether the page is
/// loading; each report that it is not ends the navigation in progress.
struct BrowserPageLoadingChanged: BrowserPageEngineEvent {
    // MARK: - Variables

    let isLoading: Bool

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        guard !isLoading else { return }
        page.linkDrag?.didFinishNavigation()
        // A navigation that failed or turned into a download ends here
        // without committing.
        page.linkHover?.didFailNavigation()
        page.mediaSessionCoordinator?.didFinishNavigation()
        if page.hasCommittedNavigationAwaitingCompletion {
            page.hasCommittedNavigationAwaitingCompletion = false
            page.completedNavigationCount += 1
        }
    }
}
