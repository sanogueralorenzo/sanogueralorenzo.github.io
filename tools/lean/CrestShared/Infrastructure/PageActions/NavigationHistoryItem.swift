import Foundation

/// One entry of a page's back or forward menu: the core's history entry it
/// returns to, and what the menu shows for it.
struct BrowserNavigationHistoryItem: Identifiable, Equatable, Sendable {
    // MARK: - Static Variables

    /// The most entries one direction of a page's history lists, nearest first,
    /// as Chromium's back and forward menus do. Farther entries stay a Back or
    /// Forward away, and History keeps every visit.
    static let listedLimit = 12

    // MARK: - Variables

    /// The history entry the item returns to, as the core names it.
    let id: UUID
    let title: String
    let url: URL

    // MARK: - Initializers

    /// The item for `entry`, titled by its host when the page gave it no
    /// title; nil for an entry whose address is not a URL.
    init?(_ entry: PageHistoryEntry) {
        guard let url = URL(string: entry.url) else { return nil }
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        id = entry.id
        self.title = title.isEmpty ? url.host() ?? url.absoluteString : title
        self.url = url
    }

    /// The items of `entries`, nearest first, as one direction of a menu
    /// lists them.
    static func listed(_ entries: [PageHistoryEntry]) -> [Self] {
        entries.prefix(listedLimit).compactMap(Self.init)
    }
}
