import Foundation

/// Context-menu destinations use the same tab-opening and access rules as the sidebar.
@MainActor
struct BrowserLinkDestinationHost {
    // MARK: - Static Variables

    static let unavailable = BrowserLinkDestinationHost()

    // MARK: - Variables

    weak var browser: BrowserStore?

    // MARK: - Actions - Link Destinations

    func canOpenLink(from source: BrowserTabRuntimeAssignment) -> Bool {
        guard let browser,
            let space = browser.selectedAvailableSpace(
                matching: BrowserSpaceRuntimeAssignment(
                    spaceID: source.spaceID, profileID: source.profileID
                ))
        else { return false }
        return space.tabs.model(source.tabID) != nil
    }

    func otherSpaces(from source: BrowserTabRuntimeAssignment) -> [SpaceModel] {
        guard canOpenLink(from: source), let browser else { return [] }
        return browser.availableTabMoveDestinationSpaces(
            from: BrowserSpaceRuntimeAssignment(
                spaceID: source.spaceID, profileID: source.profileID
            ))
    }

    func selectionSearch(
        for text: String,
        from source: BrowserTabRuntimeAssignment
    ) -> BrowserSelectionSearchDestination? {
        guard let browser else { return nil }
        browser.core.drain()
        guard canOpenLink(from: source) else { return nil }
        let text = BrowserAddress.trimmed(text)
        let provider = browser.core.state.appPreferences.searchProvider
        guard !text.isEmpty, let url = URL(string: provider.search(text)), ExternalWebLink.accepts(url) else {
            return nil
        }
        return BrowserSelectionSearchDestination(url: url, engineTitle: provider.title, source: source)
    }

    @discardableResult
    func openLink(
        _ url: URL,
        from source: BrowserTabRuntimeAssignment,
        in destination: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard ExternalWebLink.accepts(url),
            canOpenLink(from: source), let browser,
            browser.availableSpace(matching: destination) != nil
        else { return false }
        guard let tabID = browser.openNewTab(url: url, matching: destination) else { return false }
        if destination.spaceID != source.spaceID {
            // Space entry must show this explicit opening, even before its page is resident.
            browser.pendingMovedTabActivation = BrowserTabRuntimeAssignment(
                tabID: tabID, spaceID: destination.spaceID, profileID: destination.profileID)
        }
        return true
    }
}

struct BrowserSelectionSearchDestination: Equatable, Sendable {
    let url: URL
    /// The name of the engine that runs the search.
    let engineTitle: String
    let source: BrowserTabRuntimeAssignment
}
