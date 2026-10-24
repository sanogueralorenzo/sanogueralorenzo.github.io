/// The engine couldn't create the page; `message` says why, in place of its
/// content.
struct BrowserPageCreationFailed: BrowserPageEngineEvent {
    // MARK: - Variables

    let message: String

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.hasCommittedNavigationAwaitingCompletion = false
        page.webContentFailureMessage = message
    }
}
