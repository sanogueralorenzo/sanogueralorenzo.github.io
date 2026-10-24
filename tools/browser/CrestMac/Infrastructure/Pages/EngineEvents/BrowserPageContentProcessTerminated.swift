/// An engine that reports its own navigations lost the page's content
/// process.
struct BrowserPageContentProcessTerminated: BrowserPageEngineEvent {
    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        // The core decides whether the page comes back and shows the failure
        // when it does not; the page drops what belonged to the document that
        // is gone.
        page.hasCommittedNavigationAwaitingCompletion = false
        page.credentialState.webContentProcessDidTerminate()
        page.mediaSessionCoordinator?.webContentProcessDidTerminate()
    }
}
