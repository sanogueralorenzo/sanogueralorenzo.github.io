import Foundation

/// What the tab surfaces draw from a tab of the read model, in their own
/// vocabulary. Each member reads only the fields it names, so a view that
/// draws one of them redraws only when those fields change.
extension TabStateModel {
    // MARK: - Variables

    /// The Start Page, which the sidebar lists nowhere.
    var isStartPage: Bool {
        surface == .startPage
    }

    var isWebPage: Bool {
        surface == .webPage
    }

    /// The address the tab shows, as the platform reads addresses.
    var address: URL? {
        url.flatMap(URL.init(string:))
    }

    /// The name the tab surfaces show, in the person's language: the
    /// person's rename, the title of the native view the tab shows, or its
    /// page's title.
    var shownTitle: String {
        guard let nativeView, BrowserShownTitle.resolve(customTitle) == nil else { return displayTitle }
        return String(localized: nativeView.title)
    }

    /// The native document the tab shows, in the vocabulary the views match.
    var nativeTabContent: BrowserNativeTabContent? {
        nativeContent.map { BrowserNativeTabContent(kind: $0.kind, resourceID: $0.resourceID) }
    }

    /// The emoji the tab wears in place of its icon, if it chose one.
    var emojiIcon: String? {
        BrowserIconSymbol.emoji(from: symbol)
    }

    /// The accent the tab's icon was given, in the vocabulary the views draw.
    var iconTint: BrowserTabIconAccent? {
        iconAccent.map { BrowserTabIconAccent(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    /// Whether a person can replace or return to the address the tab keeps.
    var supportsSavedLocationEditing: Bool {
        placement.isDurable && (savedURL ?? url) != nil
    }

    // MARK: - Actions - Titles

    /// The name the tab surfaces show, reading the tab's page in `state` when
    /// given one. A page showing a failed load is named by the site it failed
    /// to load, as the window title names it, unless the person renamed the
    /// tab. Reading it observes the page's live state.
    func shownTitle(in state: CoreState?) -> String {
        guard nativeView == nil, BrowserShownTitle.resolve(customTitle) == nil,
            let page = state?.pages.values.first(where: { $0.tabID == id && $0.phase.holdsEnginePage }),
            page.live.failure != nil, let failed = page.live.displayURL, let host = failed.host(), !host.isEmpty
        else { return shownTitle }
        return BrowserAddressPresentation(failed.absoluteString).domain
    }
}
