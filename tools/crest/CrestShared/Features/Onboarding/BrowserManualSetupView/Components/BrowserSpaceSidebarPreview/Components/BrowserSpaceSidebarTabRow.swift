import SwiftUI

struct BrowserSpaceSidebarTabRow: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let isSelected: Bool

    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    var body: some View {
        BrowserSpaceSidebarTabRowContent(
            tab: tab, favicons: favicons, profileID: profileID, isSelected: isSelected,
            tabScale: tabScale, appearance: BrowserDeviceAppearanceStore.shared.tabs
        )
    }
}
