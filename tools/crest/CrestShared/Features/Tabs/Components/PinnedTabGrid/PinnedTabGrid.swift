import SwiftUI

/// The pinned tabs as a grid of tiles, on every shell and in the previews
/// that show one.
///
/// Each tile reads its own tab, whether its window shows it and whether it is
/// selected, so showing another tab redraws the two tiles it concerns and the
/// grid itself redraws only when the pinned tabs change.
struct PinnedTabGrid: View {
    let tabs: [TabStateModel]
    let favicons: FaviconAssets
    let assignment: BrowserSpaceRuntimeAssignment
    /// The window whose shown tab a tile marks, or nil for a preview, which
    /// marks `selectedTabID`.
    var window: WindowStateModel? = nil
    var selectedTabID: UUID? = nil
    let select: (BrowserTabRuntimeAssignment) -> Void
    /// The live sidebar's lists, which organize, drag and unload tiles; nil
    /// for a preview that is only for looking at.
    var context: BrowserSidebarListContext? = nil
    var dragState: BrowserTabDragState? = nil
    var siteThemeAccent: (BrowserTabRuntimeAssignment) -> BrowserTabIconAccent? = {
        _ in nil
    }
    var promotionNamespace: Namespace.ID? = nil
    /// Input sizing, organization actions, and promotion anchors supplied by the host.
    var capabilities = BrowserInteractionCapabilities()

    var body: some View {
        PinnedTabGridContent(grid: self)
    }
}
