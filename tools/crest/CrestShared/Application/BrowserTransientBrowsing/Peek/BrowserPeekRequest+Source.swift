import Foundation

extension BrowserPeekRequest {
    // MARK: - Actions - Source

    /// Whether the tab the Peek opened from is still in its Space, which keeps
    /// its profile and is not being deleted, as the read model holds it.
    @MainActor
    func hasSource(in browser: BrowserStore) -> Bool {
        browser.spaceModel(matching: assignment)?.tabs.model(sourceTabID) != nil
    }

    /// Whether `browser`'s window shows the tab the Peek opened from.
    @MainActor
    func isSelected(in browser: BrowserStore) -> Bool {
        hasSource(in: browser) && browser.shownSpace?.id == spaceID && browser.selectedTabID(in: spaceID) == sourceTabID
    }
}
