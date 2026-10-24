import Foundation

/// The document's address changed from `previous` to `current`.
struct BrowserPageURLChanged: BrowserPageEngineEvent {
    // MARK: - Variables

    let previous: URL?
    let current: URL?

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.translation.documentURLDidChange(from: previous, to: current)
        page.refreshNavigationState()
        page.credentialState.didChangeTopLevelURL(to: current)
    }
}
