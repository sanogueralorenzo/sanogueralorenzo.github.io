import Foundation

/// The engine kept the page's document from opening `pageURL`.
struct BrowserPagePopupBlocked: BrowserPageEngineEvent {
    // MARK: - Variables

    let pageURL: URL

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.recordEngineBlockedPopup(
            pageURL: pageURL,
            documentIdentifier: String(page.committedNavigationCount)
        )
    }
}
