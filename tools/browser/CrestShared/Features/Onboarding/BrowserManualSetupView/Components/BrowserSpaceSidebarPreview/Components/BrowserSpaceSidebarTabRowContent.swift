import SwiftUI

struct BrowserSpaceSidebarTabRowContent: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let isSelected: Bool
    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.sidebarSpacePresentation) private var presentation

    let tabScale: Double
    let appearance: BrowserTabAppearance

    var body: some View {
        HStack(spacing: BrowserManualSetupSidebarPreviewMetrics.tabSpacing) {
            TabStateFaviconView(
                tab: tab,
                favicons: favicons,
                profileID: profileID,
                size: BrowserManualSetupSidebarPreviewMetrics.tabIconSize * BrowserSidebarDensity(tabScale).scale
            )
            Text(tab.shownTitle)
                .lineLimit(1)
            Spacer()
        }
        .padding(
            .horizontal,
            BrowserManualSetupSidebarPreviewMetrics.tabHorizontalPadding
        )
        .font(
            .system(
                size: BrowserSidebarDensity.bodySize(touch: capabilities.supportsTouch)
                    * BrowserSidebarDensity(tabScale).scale)
        )
        .frame(
            minHeight: BrowserSidebarDensity(tabScale).rowHeight(
                base: BrowserManualSetupSidebarPreviewMetrics.tabHeight, touch: capabilities.supportsTouch)
        )
        .modifier(
            BrowserTabAppearanceSurface(
                appearance: appearance,
                accent: (appearance.color ?? presentation?.branding.primaryColor
                    ?? .indigo)
                    .color,
                isPinned: false, isSelected: isSelected, isHovering: false))
    }
}

#if DEBUG
    #Preview("Setup tab rows") {
        let tab = BrowserSidebarTabRowPreviewFixture.tab()
        let profileID = BrowserSidebarTabRowPreviewFixture.profileID
        let favicons = FaviconAssets()
        VStack(spacing: 12) {
            BrowserSpaceSidebarTabRowContent(
                tab: tab, favicons: favicons, profileID: profileID, isSelected: true, tabScale: 1,
                appearance: BrowserTabAppearance())
            BrowserSpaceSidebarTabRowContent(
                tab: tab, favicons: favicons, profileID: profileID, isSelected: false, tabScale: 1,
                appearance: BrowserTabAppearance())
        }.padding().frame(width: 320)
    }
#endif
