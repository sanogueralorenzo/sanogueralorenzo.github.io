import SwiftUI

struct PinnedTabSelectionButton: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let siteTheme: BrowserTabIconAccent?
    let select: () -> Void
    var isMultiSelected = false
    var branding: SpaceBranding? = nil
    /// The tab's page, whose statuses dress the tile while they last.
    var statusSource: BrowserTabStatusSource? = nil
    let iconCustomization: BrowserIconCustomizationPresentation

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.tabFaviconIsReplaced) private var isIconReplaced
    @State private var isHovering = false
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults) private
        var iconScale = 1.0

    var body: some View {
        Button(action: select) {
            icon
                .opacity(isIconReplaced ? 0 : 1)
                .font(.system(size: 17 * BrowserSidebarDensity(iconScale).scale, weight: .medium))
                .browserTabResidency(isLoaded: tab.nativeContent != nil || isLoaded)
                .browserIconCustomizationPopover(iconCustomization, arrowEdge: iconPickerArrowEdge)
                .overlay(alignment: .bottomTrailing) {
                    TabEngineBadge(tabID: tab.id, scale: BrowserSidebarDensity(iconScale).scale)
                }
                .anchorPreference(key: TabFaviconBoundsKey.self, value: .bounds) { $0 }
                .frame(maxWidth: .infinity)
                .frame(
                    height: BrowserSidebarDensity(iconScale).pinHeight(touch: capabilities.supportsTouch)
                )
                .contentShape(.rect)
                .modifier(
                    PinnedTabInteractionSurface(
                        favicon: tab.iconMode.showsFavicon ? favicons.icon(of: tab.id) : nil,
                        siteTheme: siteTheme,
                        isSelected: isSelected,
                        isHovering: isHovering || isMultiSelected,
                        isMultiSelected: isMultiSelected,
                        branding: branding,
                        statusSource: statusSource
                    )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var icon: some View {
        TabStateFaviconView(
            tab: tab, favicons: favicons, profileID: profileID, size: 19 * BrowserSidebarDensity(iconScale).scale)
    }

    private var iconPickerArrowEdge: Edge? {
        #if os(macOS)
            .leading
        #else
            // Let the native popover fit around the pin on either sidebar side.
            // A forced leading arrow clips the picker beside a right-docked sidebar.
            nil
        #endif
    }
}
