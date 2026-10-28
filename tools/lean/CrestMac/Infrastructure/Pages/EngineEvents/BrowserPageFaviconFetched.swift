import Foundation

/// An icon the engine fetched. `source` names the document it belongs to;
/// nil means the current one.
struct BrowserPageFaviconFetched: BrowserPageEngineEvent {
    // MARK: - Variables

    let data: Data?
    let source: URL?

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        if let source {
            guard let url = page.pageEngine.currentURL,
                SamePage.restoresArchivedState(archivedURL: source, tabURL: url)
            else { return }
        }
        page.faviconData = data
    }
}
