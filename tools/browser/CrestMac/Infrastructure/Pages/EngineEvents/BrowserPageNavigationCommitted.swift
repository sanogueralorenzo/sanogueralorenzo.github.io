import Foundation

/// An engine that reports its own navigations committed a new document at
/// `url`, which finished too unless it still loads.
struct BrowserPageNavigationCommitted: BrowserPageEngineEvent {
    // MARK: - Variables

    let url: URL?
    let isLoading: Bool

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.hasCommittedNavigationAwaitingCompletion = isLoading
        page.isContentFullscreen = false
        page.webContentFailureMessage = nil
        page.linkHover?.didCommitNavigation()
        page.mediaSessionCoordinator?.didCommitNavigation()
        page.committedNavigationCount += 1
        if !isLoading { page.completedNavigationCount += 1 }
        let authentication = page.httpAuthenticationSession
        Task { await authentication.authenticationSucceeded() }
        page.synchronizePopupPermission(for: url)
        page.sitePermissionSession.synchronize(for: url)
    }
}
