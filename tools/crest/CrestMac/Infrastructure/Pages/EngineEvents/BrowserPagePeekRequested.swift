import Foundation

/// The engine kept a link in the page for the Peek the core chose, with the
/// link it staged for the Peek's first load, if any.
struct BrowserPagePeekRequested: BrowserPageEngineEvent {
    // MARK: - Variables

    let destination: URL
    let decision: LinkNavigationDecision
    let stagedLink: BrowserEngineNavigation?

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.openRequestedPeek(to: destination, decision: decision, stagedLink: stagedLink)
    }
}
