import Foundation

/// The pointer moved onto a link, or off every link when `destination` is
/// nil.
struct BrowserPageLinkHovered: BrowserPageEngineEvent {
    // MARK: - Variables

    let destination: URL?

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.linkHover?.receiveEngineHover(destination)
    }
}
