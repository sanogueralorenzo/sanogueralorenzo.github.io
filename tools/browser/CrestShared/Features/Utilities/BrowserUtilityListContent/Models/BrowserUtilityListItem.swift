import SwiftUI

enum BrowserUtilityListItem: Identifiable, Sendable {
    case archive(ArchivedTabState)
    case history(HistoryEntryState)
    case download(DownloadState)

    var id: BrowserUtilityListItemID {
        switch self {
        case .archive(let item): .archive(item.tab.id)
        case .history(let item): .history(item.id)
        case .download(let item): .download(item.id)
        }
    }

    var date: Date {
        switch self {
        case .archive(let item): item.archivedAt
        case .history(let item): item.lastVisitedAt
        case .download(let item): item.createdAt
        }
    }

    /// Whether a search for `query` finds the item by its words: an empty
    /// search finds every item.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        switch self {
        case .archive(let archived):
            return archived.tab.shownTitle.localizedStandardContains(query)
                || archived.tab.url?.localizedStandardContains(query) == true
        case .history(let entry):
            return entry.title.localizedStandardContains(query)
                || entry.url.localizedStandardContains(query)
        case .download(let download):
            return download.filename.localizedStandardContains(query)
                || BrowserDownloadRowPresentation.status(of: download)
                    .resolvedForSearch()
                    .localizedStandardContains(query)
        }
    }
}

enum BrowserUtilityListItemID: Hashable, Sendable {
    case archive(UUID)
    case history(UUID)
    case download(UUID)
}

struct BrowserUtilityListSection: Identifiable, Sendable {
    let timeframe: BrowserUtilityTimeSection
    let items: [BrowserUtilityListItem]

    var id: String { timeframe.id }
}

extension EnvironmentValues {
    /// The images the tabs a utility list shows wear, which the list's host
    /// reads from the core's read model.
    @Entry var browserFavicons: FaviconAssets? = nil
}
