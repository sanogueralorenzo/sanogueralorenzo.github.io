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

}
