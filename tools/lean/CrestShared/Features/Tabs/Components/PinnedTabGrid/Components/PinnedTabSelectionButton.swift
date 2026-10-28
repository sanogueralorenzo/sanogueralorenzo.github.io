import SwiftUI

struct PinnedTabSelectionButton: View {
    // MARK: - Variables

    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let siteTheme: BrowserTabIconAccent?
    let select: () -> Void
    var isMultiSelected = false

    /// The tab's page, whose statuses dress the tile while they last.
    var statusSource: BrowserTabStatusSource? = nil
    var returnToSavedURL: (() -> Void)?

    @Environment(\.browserShortcutBindings) private var shortcutBindings

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.tabFaviconIsReplaced) private var isIconReplaced
    @State private var isHovering = false
    private let iconScale = 1.0

    // MARK: - Actions - Content

    var body: some View {
        HStack(spacing: CrestSpacing.extraSmall) {
            Button(action: select) {
                icon
                    .opacity(isIconReplaced ? 0 : 1)
                    .font(.system(size: 17 * BrowserSidebarDensity(iconScale).scale, weight: .medium))
                    .browserTabResidency(isLoaded: tab.nativeContent != nil || isLoaded)
                    .overlay(alignment: .bottomTrailing) {
                        TabEngineBadge(tabID: tab.id, scale: BrowserSidebarDensity(iconScale).scale)
                    }
                    .anchorPreference(key: TabFaviconBoundsKey.self, value: .bounds) { $0 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(
                CrestChromeButtonStyle(
                    controlSize: nil, cornerRadius: BrowserSidebarMetrics.capsuleRadius(tabScale: 1),
                    cornerStyle: .circular)
            )
            .accessibilityLabel(tab.shownTitle)
            if isSelected {
                BrowserShortcutHint(shortcut: ShortcutCommand.closeTabOrWindow.shortcut(in: shortcutBindings))
                if let returnToSavedURL {
                    Button(action: returnToSavedURL) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: capabilities.trailingControlMetrics.glyphSize, weight: .medium))
                    }
                    .buttonStyle(
                        CrestChromeButtonStyle(
                            controlSize: capabilities.trailingControlMetrics.controlSize,
                            cornerRadius: capabilities.trailingControlMetrics.cornerRadius, cornerStyle: .circular)
                    )
                    .accessibilityLabel("Return to Saved URL")
                    .accessibilityIdentifier("return-tab-to-saved-url")
                    .help("Return to Saved URL")
                }
            }
        }
        .padding(.horizontal, CrestSpacing.extraSmall)
        .frame(maxWidth: .infinity)
        .frame(height: BrowserSidebarDensity(iconScale).pinHeight(touch: capabilities.supportsTouch))
        .modifier(
            PinnedTabInteractionSurface(
                favicon: tab.iconMode.showsFavicon ? favicons.icon(of: tab.id) : nil,
                siteTheme: siteTheme,
                isSelected: isSelected,
                isHovering: isHovering || isMultiSelected,
                isMultiSelected: isMultiSelected,
                statusSource: statusSource
            )
        )
        .onHover { isHovering = $0 }
    }

    private var icon: some View {
        TabStateFaviconView(
            tab: tab, favicons: favicons, profileID: profileID, size: 19 * BrowserSidebarDensity(iconScale).scale)
    }
}

#if DEBUG
    #Preview("Pinned tab chip") {
        PinnedTabSelectionButton(
            tab: BrowserSidebarTabRowPreviewFixture.tab(placement: .pinned),
            favicons: FaviconAssets(),
            profileID: BrowserSidebarTabRowPreviewFixture.profileID,
            isSelected: false,
            isLoaded: false,
            siteTheme: nil,
            select: {}
        )
        .padding()
        .frame(width: 160)
    }
#endif
