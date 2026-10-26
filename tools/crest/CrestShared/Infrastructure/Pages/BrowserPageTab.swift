import Foundation

/// A tab as its page takes it: the core's record of the tab and the icon this
/// platform keeps for it, which never reaches the core.
struct BrowserPageTab: Equatable {
    // MARK: - Variables

    let state: TabState
    /// The icon this platform keeps for the tab, whatever its icon mode.
    let faviconData: Data?

    var id: UUID { state.id }

    /// The address the tab shows, as the platform reads addresses.
    var url: URL? { state.url.flatMap(URL.init(string:)) }

    /// The native document the tab shows, if it shows one.
    var nativeContent: BrowserNativeTabContent? {
        state.nativeContent.map { BrowserNativeTabContent(kind: $0.kind, resourceID: $0.resourceID) }
    }

    /// The icon the tab wears, when its mode shows a favicon.
    var displayFaviconData: Data? {
        state.iconMode.showsFavicon ? faviconData : nil
    }

    /// The icon follows the page, and the platform holds the favicon the core
    /// says was taken from the page the tab shows.
    var hasCurrentAutomaticFavicon: Bool {
        state.pageIconIsCurrent && faviconData != nil
    }

    // MARK: - Initializers

    init(state: TabState, faviconData: Data?) {
        self.state = state
        self.faviconData = faviconData
    }

    /// The tab of the read model, wearing the icon `images` keeps for it.
    @MainActor
    init(_ tab: TabStateModel, images: FaviconAssets) {
        self.init(state: tab.value, faviconData: images.image(of: tab.id))
    }

}
