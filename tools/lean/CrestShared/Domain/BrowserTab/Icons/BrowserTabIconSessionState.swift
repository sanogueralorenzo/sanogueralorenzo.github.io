import Foundation

/// What a tab's page icon follows: the tab's address and icon choices, and
/// the icon this platform keeps for it.
struct BrowserTabIconSessionItem: Equatable, Sendable {
    let id: UUID
    let url: String?
    let faviconData: Data?
    let faviconURL: String?
    let iconAccent: TabIconAccent?
    let iconMode: TabIconMode
    let symbol: String
}

/// What every tab's page icon follows in one workspace, compared between
/// changes so pages are given their tabs' icons only when one moved.
struct BrowserTabIconSessionState: Equatable, Sendable {
    typealias Item = BrowserTabIconSessionItem

    let items: [Item]

    init(items: [Item]) {
        self.items = items
    }

    /// The tabs of `workspace` in the read model, wearing the icons `images`
    /// keeps.
    @MainActor
    init(workspace: WorkspaceModel?, images: FaviconAssets) {
        self.init(
            items: (workspace?.spaces.models ?? []).flatMap { space in
                space.tabs.models.map { tab in
                    Item(
                        id: tab.id, url: tab.url, faviconData: images.image(of: tab.id), faviconURL: tab.faviconURL,
                        iconAccent: tab.iconAccent, iconMode: tab.iconMode, symbol: tab.symbol)
                }
            })
    }
}
