/// An engine that reports its own navigations failed one; its reporter told
/// the core why.
struct BrowserPageNavigationFailed: BrowserPageEngineEvent {
    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        // The core shows the failure until a navigation commits: the engine
        // retries a network error on its own, and a retry that fails again
        // commits no new error page.
        page.hasCommittedNavigationAwaitingCompletion = false
        page.httpAuthenticationSession.authenticationFailed()
    }
}
