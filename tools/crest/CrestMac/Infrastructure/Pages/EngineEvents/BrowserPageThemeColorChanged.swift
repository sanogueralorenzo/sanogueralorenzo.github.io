import AppKit

/// The colour the document asks its surroundings to take, if any.
struct BrowserPageThemeColorChanged: BrowserPageEngineEvent {
    // MARK: - Variables

    let color: NSColor?

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.themeColor = color
    }
}
