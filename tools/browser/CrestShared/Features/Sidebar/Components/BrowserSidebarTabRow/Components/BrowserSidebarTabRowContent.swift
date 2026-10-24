import SwiftUI

/// What a sidebar tab row draws inside its surface: the tab, and the one
/// control that puts it away.
struct BrowserSidebarTabRowContent: View {
    let configuration: BrowserSidebarTabRowConfiguration
    let interaction: BrowserSidebarTabRowInteractionContext

    var body: some View {
        HStack(spacing: configuration.metrics.contentSpacing) {
            leadingContent
            BrowserSidebarTabTrailingControl(
                configuration: configuration,
                isHovering: interaction.isHovering
            )
            .padding(.trailing, configuration.metrics.contentTrailingInset)
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        if interaction.isRenaming {
            BrowserSidebarTabRenameField(
                tab: configuration.tab,
                favicons: configuration.favicons,
                profileID: configuration.profileID,
                metrics: configuration.metrics,
                leadingInset: configuration.metrics.contentLeadingInset,
                draftTitle: interaction.draftTitle,
                isTitleFocused: interaction.isTitleFocused,
                commitTitle: interaction.commitTitle,
                cancelTitleEditing: interaction.cancelTitleEditing
            )
        } else {
            BrowserSidebarTabActivationButton(
                tab: configuration.tab,
                favicons: configuration.favicons,
                profileID: configuration.profileID,
                isSelected: configuration.isSelected,
                isLoaded: configuration.isLoaded,
                metrics: configuration.metrics,
                leadingInset: configuration.metrics.contentLeadingInset,
                restoreSavedLocation: configuration.restoreSavedLocation,
                iconCustomization: BrowserIconCustomizationPresentation(
                    isPresented: interaction.isChoosingIcon,
                    title: "Tab Icon",
                    currentEmoji: configuration.tab.emojiIcon,
                    // Reset applies to explicit icon overrides.
                    showsReset: !configuration.tab.iconMode.followsPage,
                    resetTitle: "Use Website Icon",
                    setEmoji: interaction.setEmojiIcon,
                    reset: interaction.resetIcon
                ),
                select: interaction.activate
            )
            .modifier(
                BrowserTabSelectionAccessibility(
                    tabID: configuration.tab.id, spaceID: configuration.spaceID, browser: configuration.browser,
                    isActive: configuration.isSelected, isLoaded: configuration.isLoaded))
        }
    }
}
