import SwiftUI

struct BrowserSpaceSidebarTabRow: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let isSelected: Bool

    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults)
    private var tabScale = 1.0

    var body: some View {
        BrowserSpaceSidebarTabRowContent(
            tab: tab, favicons: favicons, profileID: profileID, isSelected: isSelected,
            tabScale: tabScale, appearance: BrowserDeviceAppearanceStore.shared.tabs
        )
    }
}
