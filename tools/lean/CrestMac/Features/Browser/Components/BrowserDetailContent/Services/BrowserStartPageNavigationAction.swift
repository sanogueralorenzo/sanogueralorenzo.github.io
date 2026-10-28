import Foundation

@MainActor
struct BrowserStartPageNavigationAction {
    let browser: BrowserStore
    let pages: BrowserPagePool

    func perform(_ source: BrowserTabRuntimeAssignment, url: URL) -> Bool {
        guard
            browser.isPaletteSourceAvailable(source),
            browser.shownTab?.surface == .startPage
        else { return false }
        browser.navigateSelectedTab(to: url.absoluteString)
        // A cold launch or unloaded Space has no active page to receive load().
        // Selecting materializes the draft's page and starts its initial URL.
        pages.select()
        return true
    }
}
