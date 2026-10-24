import SwiftUI

struct SpaceSidebarUtilityContent: View {
    let surface: BrowserUtilitySurface
    let space: SpaceModel
    let favicons: FaviconAssets
    @Binding var searchText: String
    @Binding var filter: BrowserUtilityListFilter
    let commandSurfaceNamespace: Namespace.ID
    let downloads: [DownloadState]
    let actions: BrowserUtilityListActions
    let dismissOnBlankSpace: () -> Void
    let clearHistory: () -> Void
    var searchFocusRequest = 0
    var consumeSearchFocusRequest: @MainActor (Int, BrowserUtilitySurface) -> Bool = { _, _ in false }

    @Environment(\.sidebarSpaceIsSelected) private var isSelected

    var body: some View {
        if isSelected != false {
            BrowserUtilitySearchToolbar(
                surface: surface,
                searchText: $searchText,
                filter: $filter,
                morphNamespace: commandSurfaceNamespace,
                morph: .utilitySearch(spaceID: space.id),
                clearHistory: clearHistory,
                focusRequest: searchFocusRequest,
                consumeFocusRequest: consumeSearchFocusRequest
            )
            .padding(.horizontal, BrowserSidebarMetrics.layerInset)
            .padding(.bottom, CrestSpacing.extraSmall)
            .transition(.opacity.combined(with: .move(edge: .trailing)))

            BrowserUtilityListContent(
                surface: surface,
                space: space,
                downloads: downloads,
                searchText: searchText,
                filter: filter,
                actions: actions,
                dismissOnBlankSpace: dismissOnBlankSpace,
                favicons: favicons
            )
            .transition(.opacity)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
}
