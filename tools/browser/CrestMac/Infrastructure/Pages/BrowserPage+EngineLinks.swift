import AppKit

/// Link destinations for an engine that asks the core about its links itself
/// and runs its own link menu and drags. They run the same shared commands the
/// WebKit menu and navigation delegate use.
extension BrowserPage {
    /// Opens `url` as a new card beside the tab this page presents.
    func openLinkInSplitView(_ url: URL) {
        guard let context = navigationContext,
            ExternalWebLink.accepts(url)
        else { return }
        _ = splitLinkHost.openLink(url, context.tabID, context.assignment)
    }

    /// Opens the Peek the core chose for a link the engine kept in the page.
    /// A page that has no tab to open it from, or is out of its window, drops
    /// the link its engine staged for the Peek's first load.
    func openRequestedPeek(
        to destination: URL, decision: LinkNavigationDecision, stagedLink: BrowserEngineNavigation?
    ) {
        guard nativeView.window != nil,
            let request = decision.peekRequest(
                destinationURL: destination, context: navigationContext, engineNavigation: stagedLink)
        else {
            if let stagedLink { corePage.discardStagedLink(stagedLink) }
            return
        }
        openPeek(request)
    }
}
