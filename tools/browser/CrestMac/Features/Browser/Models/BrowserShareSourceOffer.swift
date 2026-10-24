import Foundation

/// A page asked to share the screen, and the engine offers the person the
/// tabs it may share before the system's picker offers a window or a
/// display. The person answers once; the engine withdraws the offer when the
/// request ends first.
struct BrowserShareSourceOffer: Identifiable, Equatable {
    // MARK: - Types

    /// A tab the person can share.
    struct Tab: Identifiable, Equatable {
        // MARK: - Variables

        /// The tab's page.
        let id: UUID
        let title: String
        let url: URL?
        let icon: Data?

        /// What the picker calls the tab: its title, or its address when it
        /// has none.
        var displayTitle: String {
            if !title.isEmpty { return title }
            return url?.host() ?? url?.absoluteString ?? ""
        }
    }

    /// Where a page's tab sits in its Space and what the sidebar calls it.
    struct TabPlacement: Equatable {
        let position: Int
        let name: String
    }

    /// What the person chose, as the engine's answer carries it.
    struct Choice: Equatable {
        // MARK: - Static Variables

        /// A window or a display, which the system's picker asks for next.
        static let windowOrScreen = Choice(kind: .windowOrScreen, tabPageID: nil, sharesAudio: false)
        /// Nothing: the request is refused.
        static let cancel = Choice(kind: .cancel, tabPageID: nil, sharesAudio: false)

        // MARK: - Variables

        let kind: ShareSourceChoice
        /// The page of the tab chosen, for a tab.
        let tabPageID: UUID?
        /// Whether the chosen tab's sound is shared too.
        let sharesAudio: Bool

        // MARK: - Actions - Choosing

        /// The tab whose page is `pageID`, with its sound when `audio`.
        static func tab(pageID: UUID, audio: Bool) -> Choice {
            Choice(kind: .tab, tabPageID: pageID, sharesAudio: audio)
        }
    }

    // MARK: - Variables

    /// The engine's identity for the offer.
    let id: UUID
    /// The site that asks, as the person reads it.
    let site: String
    let tabs: [Tab]
    /// Whether the site asked for audio too, which a shared tab can carry.
    let asksAudio: Bool

    // MARK: - Actions - Ordering

    /// The offer's tabs in the order the sidebar lists them, named as it
    /// names them. `placement` answers where the tab holding a page sits in
    /// its Space and what it is called; a page it cannot place keeps the
    /// engine's order after the rest, under the page's own title.
    func tabsInSidebarOrder(placement: (UUID) -> TabPlacement?) -> [Tab] {
        tabs.map { tab in (tab: tab, placement: placement(tab.id)) }
            .enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.placement?.position ?? Int.max
                let right = rhs.element.placement?.position ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }
            .map { entry in
                guard let name = entry.element.placement?.name, !name.isEmpty else { return entry.element.tab }
                return Tab(
                    id: entry.element.tab.id, title: name, url: entry.element.tab.url, icon: entry.element.tab.icon)
            }
    }
}

extension BrowserShareSourceOffer {
    init(_ offered: ShareSourcesOffered) {
        self.init(
            id: offered.shareID,
            site: offered.site,
            tabs: offered.tabs.map { tab in
                Tab(id: tab.pageID, title: tab.title, url: tab.url.flatMap(URL.init(string:)), icon: tab.icon)
            },
            asksAudio: offered.audio)
    }
}
