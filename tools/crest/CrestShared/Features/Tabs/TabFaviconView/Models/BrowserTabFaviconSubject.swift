import Foundation

/// What a tab's icon is drawn from: the tab, what it shows, how it chose its
/// icon and the image it wears. Two subjects are equal when they would draw
/// the same icon; the image is compared by its fingerprint, never its bytes.
struct BrowserTabFaviconSubject: Equatable {
    // MARK: - Variables

    let tabID: UUID
    let pageURL: URL?
    let iconMode: TabIconMode
    let symbol: String
    let nativeContent: BrowserNativeTabContent?
    let isStartPage: Bool
    /// The image the tab shows as its icon: the one it wears while its icon
    /// mode shows a favicon, and none otherwise.
    let image: FaviconAssets.Image?

    var emoji: String? {
        BrowserIconSymbol.emoji(from: symbol)
    }

    // MARK: - Initializers

    /// A tab of the read model wearing `image`, the one `FaviconAssets` holds
    /// for it.
    @MainActor
    init(tab: TabStateModel, image: FaviconAssets.Image?) {
        tabID = tab.id
        pageURL = tab.address
        iconMode = tab.iconMode
        symbol = tab.symbol
        nativeContent = tab.nativeTabContent
        isStartPage = tab.isStartPage
        self.image = tab.iconMode.showsFavicon ? image : nil
    }

    /// A tab the core published outside the read model's tab lists, such as
    /// an archived one, wearing `image`.
    init(tab: TabState, image: FaviconAssets.Image?) {
        tabID = tab.id
        pageURL = tab.url.flatMap(URL.init(string:))
        iconMode = tab.iconMode
        symbol = tab.symbol
        nativeContent = tab.nativeContent.map { BrowserNativeTabContent(kind: $0.kind, resourceID: $0.resourceID) }
        isStartPage = tab.surface == .startPage
        self.image = tab.iconMode.showsFavicon ? image : nil
    }

    // MARK: - Actions - Rendering

    /// The identity of the task that renders this icon at up to
    /// `maximumPixelSize` for `profileID`.
    func taskIdentity(
        profileID: UUID?,
        maximumPixelSize: Int,
        isUnlocked: Bool = true
    ) -> BrowserFaviconTaskIdentity {
        BrowserFaviconTaskIdentity(
            tabID: tabID,
            profileID: profileID,
            pageURL: pageURL,
            iconMode: iconMode.name,
            // The image carries the fingerprint taken when it was set. SwiftUI
            // evaluates this identity during every view update, so nothing
            // here may read the image bytes.
            payload: image?.identity,
            maximumPixelSize: maximumPixelSize,
            isUnlocked: isUnlocked
        )
    }

    /// A locked Space must never reach the network for an icon: the request that
    /// fetches `https://<host>/favicon.ico` would disclose the hostnames the lock
    /// exists to hide, and would cache them under the locked Space's profile.
    /// Redaction is a drawing effect and cannot stop that, so the fallback is
    /// dropped at the request itself.
    func renderRequest(
        profileID: UUID?,
        maximumPixelSize: Int,
        isUnlocked: Bool = true
    ) -> BrowserFaviconRenderRequest {
        let identity = taskIdentity(
            profileID: profileID,
            maximumPixelSize: maximumPixelSize,
            isUnlocked: isUnlocked
        )
        guard !isStartPage, emoji == nil, isUnlocked else {
            return BrowserFaviconRenderRequest(
                identity: identity,
                payload: nil,
                fallbackPageURL: nil,
                fallbackProfileID: nil
            )
        }

        let payload = image?.data
        return BrowserFaviconRenderRequest(
            identity: identity,
            payload: payload,
            fallbackPageURL: payload == nil ? pageURL : nil,
            fallbackProfileID: payload == nil ? profileID : nil
        )
    }
}
