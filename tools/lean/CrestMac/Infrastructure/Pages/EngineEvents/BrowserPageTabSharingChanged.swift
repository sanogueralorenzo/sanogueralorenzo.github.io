/// The page's part in tab sharing changed: shared by another page, or
/// sharing another tab.
struct BrowserPageTabSharingChanged: BrowserPageEngineEvent {
    // MARK: - Variables

    let shared: Bool
    let sharing: Bool

    // MARK: - Actions - Page

    func apply(to page: BrowserPage) {
        page.isSharedAsTab = shared
        page.isSharingTab = sharing
        if !sharing { page.sharedTabPageIDs = [] }
    }
}
