import SwiftUI

/// The iPad content area, and the one place that decides between real columns and
/// the single rounded page surface.
///
/// The branch itself is `BrowserPageSurfacePresentation`'s, shared with macOS. It
/// is *applied* here rather than inside `BrowserRootDetailSurface` because the
/// columns view *replaces* that surface instead of living inside it: it applies
/// the outer page insets itself and wraps each card in its own
/// `BrowserRootContentSurface`, so nesting the two would draw a bordered, shadowed
/// surface inside another one. macOS applies the same answer at the same level in
/// `BrowserRootPageSurface`.
///
/// It is also where a tab dragged out of the sidebar becomes a card, through the
/// very modifiers macOS registers — the content area as a zone, the presented
/// cards as frames — plus the one thing a touch shell has to add: a feed that
/// carries the finger's positions to the reorder state while it is over the page.
struct MobileRegularPageSurface: View {
    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement
    let model: MobileBrowserRootModel
    let adjoinsSidebar: Bool
    let usesBorderlessPageFrame: Bool
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let addressFocusRequest: Int
    let isCommandPalettePresented: Bool
    /// The window's commands, for the Start Page's palette.
    let commands: BrowserCommandPaletteCommandRegistry
    let compactToolbarIsHidden: Bool
    let submitAddress: () -> Void
    let beginNewTab: () -> Void
    let showTabViewer: () -> Void
    let hideCompactToolbar: () -> Void
    let showCompactToolbar: () -> Void
    let showSwipedTab: (UUID) -> Void
    let compactTransitionEnded: (CGSize) -> Void

    private var pageSurfacePresentation: BrowserPageSurfacePresentation {
        let space = model.browser.shownSpace
        return BrowserPageSurfacePresentation(
            space: space,
            isLocked: space.map(model.spaceAccess.isLocked) ?? false,
            cards: model.browser.shownCards,
            hasEnteredSplitContent:
                model.sidebarInteraction.sidebarReorderState.hasEnteredSplitContent,
            resolvedTarget: model.sidebarInteraction.sidebarReorderState.resolvedTarget,
            presentsTrailingPanel: false
        )
    }

    var body: some View {
        let presentation = pageSurfacePresentation
        return surface(presentation)
            .browserSplitContentDropZone(
                assignment: presentation.dropAssignment,
                state: model.sidebarInteraction.sidebarReorderState
            )
            .modifier(
                MobileSplitContentDropFeed(
                    browser: model.browser,
                    spaceAccess: model.spaceAccess
                )
            )
    }

    @ViewBuilder
    private func surface(
        _ presentation: BrowserPageSurfacePresentation
    ) -> some View {
        if case .columns(let space, let members, let placeholderIndex) =
            presentation
        {
            MobileSplitColumnsPageSurface(
                model: model,
                space: space,
                members: members,
                adjoinsSidebar: adjoinsSidebar,
                placeholderIndex: placeholderIndex
            )
        } else {
            BrowserRootDetailSurface(
                adjoinsLeadingSidebar: adjoinsSidebar,
                usesBorderlessFrame: usesBorderlessPageFrame,
                isStartPage: model.browser.shownTab.map { $0.surface == .startPage } ?? true,
                hasActivePage: model.selectedPage != nil,
                completedNavigationCount:
                    model.selectedPage?.completedNavigationCount ?? 0,
                hasSelectedSpace: model.browser.shownSpace != nil,
                handleWebContentInteraction: {
                    model.navigation.utilityPresentation
                        .handleInteraction(.webContent)
                    model.navigation.handleRegularPageInteraction()
                },
                frameInsets: controlPlacement.pageInsets,
                content: MobileBrowserDetailSurface(
                    browser: model.browser,
                    pages: model.pages,
                    spaceAccess: model.spaceAccess,
                    address: $address,
                    isAddressEditing: $isAddressEditing,
                    addressFocusRequest: addressFocusRequest,
                    isCommandPalettePresented: isCommandPalettePresented,
                    commands: commands,
                    isCompact: false,
                    obscuresSystemSafeAreas: false,
                    showsCompactToolbar: false,
                    compactToolbarIsHidden: compactToolbarIsHidden,
                    handleWebContentInteraction: {
                        model.navigation.utilityPresentation
                            .handleInteraction(.webContent)
                        model.navigation.handleRegularPageInteraction()
                    },
                    submitAddress: submitAddress,
                    beginNewTab: beginNewTab,
                    showTabViewer: showTabViewer,
                    hideCompactToolbar: hideCompactToolbar,
                    showCompactToolbar: showCompactToolbar,
                    showSwipedTab: showSwipedTab,
                    compactTransitionEnded: compactTransitionEnded
                )
            )
            .overlay {
                MobileRegularPageSwipeBorder(adjoinsSidebar: adjoinsSidebar, page: model.selectedPage)
            }
            // The lone tab on show is a card as far as a drag is concerned: it
            // is what a dropped tab would join, and the side of it the finger
            // is on is which side of it the new card lands.
            .browserSplitDropCardFrame(
                tabID: presentation.singleCardTabID,
                assignment: presentation.dropAssignment,
                state: model.sidebarInteraction.sidebarReorderState
            )
        }
    }
}

/// The history swipe border around the page on show. It reads the window's
/// frame where it draws it, so a drag of the border never rebuilds the page.
private struct MobileRegularPageSwipeBorder: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement
    let adjoinsSidebar: Bool
    let page: MobileBrowserPage?

    var body: some View {
        MobileHistorySwipeBorder(
            insets: controlPlacement.pageInsets(
                BrowserChromeAppearance.device(windowCornerRadius: nil)
                    .pageInsets(docked: adjoinsSidebar, direction: layoutDirection)),
            leadingPage: page,
            trailingPage: page
        )
    }
}
