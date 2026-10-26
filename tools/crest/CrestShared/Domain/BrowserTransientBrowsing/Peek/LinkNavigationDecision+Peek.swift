import Foundation

/// Engine-neutral policy result. Native views only construct the presentation
/// after the core has selected the destination's browsing behavior.
extension LinkNavigationDecision {
    func peekRequest(
        destinationURL: URL?,
        context: BrowserPageNavigationContext?,
        sourcePresentation: BrowserPeekSourcePresentation? = nil,
        engineNavigation: BrowserEngineNavigation? = nil
    ) -> BrowserPeekRequest? {
        guard opensPeek, let destinationURL, let context else { return nil }
        return BrowserPeekRequest(
            url: destinationURL, sourceTabID: context.tabID, sourceTitle: context.title,
            spaceAssignment: context.assignment, trigger: protectsSavedSite ? .protectedSavedSite : .modifierClick,
            sourcePresentation: sourcePresentation, engineNavigation: engineNavigation)
    }
}
