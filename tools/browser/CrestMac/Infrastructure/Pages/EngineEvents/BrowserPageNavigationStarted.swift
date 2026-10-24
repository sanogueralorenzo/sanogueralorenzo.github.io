/// The engine started a navigation. What belonged to the document the page
/// leaves ends with it.
struct BrowserPageNavigationStarted: BrowserPageEngineEvent {
    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.hasCommittedNavigationAwaitingCompletion = false
        page.translation.reset()
        page.linkDrag?.beginNavigation()
        page.linkHover?.beginNavigation()
        page.credentialState.didStartNavigation()
        page.beginBlockedPopupNavigation()
        // A prompt the engine withdrew with its document has no one to answer.
        page.sitePermissionRequests.cancelAll()
        page.mediaSessionCoordinator?.prepareForNavigation()
        page.removeWebNotifications()
    }
}
