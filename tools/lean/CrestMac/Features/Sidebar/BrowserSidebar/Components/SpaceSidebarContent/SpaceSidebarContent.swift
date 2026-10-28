import SwiftUI

struct SpaceSidebarContent: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    let space: SpaceModel
    let browser: BrowserStore
    let pages: BrowserPagePool
    let capabilities: BrowserInteractionCapabilities
    let openNewTab: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID
    let utilitySurface: BrowserUtilitySurface?
    @Binding var utilitySearchText: String
    @Binding var utilityFilter: BrowserUtilityListFilter
    let utilityDownloads: [DownloadState]
    let utilityActions: BrowserUtilityListActions
    let dismissUtilityOnBlankSpace: () -> Void
    let clearHistory: () -> Void
    var utilitySearchFocusRequest = 0
    var consumeUtilitySearchFocusRequest: @MainActor (Int, BrowserUtilitySurface) -> Bool = { _, _ in false }

    var body: some View {
        VStack(spacing: 0) {
            if utilitySurface == nil, !browser.isDeleting(space.id) {
                BrowserEngineSidebarAccessory(space: space, browser: browser, pages: pages)
                    // Above the pinned tabs, so the selected pin's glow slides under it.
                    .zIndex(1)
            }
            Group {
                if let utilitySurface {
                    SpaceSidebarUtilityContent(
                        surface: utilitySurface,
                        space: space,
                        favicons: browser.core.state.favicons,
                        searchText: $utilitySearchText,
                        filter: $utilityFilter,
                        commandSurfaceNamespace: commandSurfaceNamespace,
                        downloads: utilityDownloads,
                        actions: utilityActions,
                        dismissOnBlankSpace: dismissUtilityOnBlankSpace,
                        clearHistory: clearHistory,
                        searchFocusRequest: utilitySearchFocusRequest,
                        consumeSearchFocusRequest: consumeUtilitySearchFocusRequest
                    )
                } else {
                    SpaceSidebarBrowsingContent(
                        space: space,
                        browser: browser,
                        pages: pages,
                        capabilities: capabilities,
                        openNewTab: openNewTab,
                        tabPromotionNamespace: tabPromotionNamespace
                    )
                }
            }
        }
        .onChange(of: utilitySurface != nil) { _, isPresented in
            // The utility surface replaces every browsing input host.
            if isPresented { sidebarInteraction.cancel() }
        }
    }

}
