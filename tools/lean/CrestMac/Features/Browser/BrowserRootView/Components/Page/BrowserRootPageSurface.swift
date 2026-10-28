import SwiftUI

/// The macOS content area, and the one place that decides between real columns
/// and the single rounded page surface.
///
/// The branch is `BrowserPageSurfacePresentation`'s rather than this view's, so
/// iPadOS opens and closes its columns on exactly the same conditions. What is
/// left here is macOS's half: which surface draws the answer, and what the
/// pointer may do to it.
struct BrowserRootPageSurface: View, @MainActor Equatable {
    @Environment(\.spaceContentPresentation) private var contentPresentation
    @Environment(\.browserMacWindows) private var windows
    let model: BrowserRootModel
    let space: SpaceModel
    let isSelectedSpace: Bool
    let tabPromotionNamespace: Namespace.ID
    /// The chords the window's commands show in a Start Page's palette.
    let shortcuts: BrowserShortcutStore?
    var layoutDirection = LayoutDirection.leftToRight

    /// The retained host needs a new root only when its inputs change. The
    /// models publish their own changes directly to the views that read them,
    /// the window's frame among them: the frame views read it from
    /// ``BrowserDeviceAppearanceStore`` themselves, so a border drag never
    /// rebuilds the page inside.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.space === rhs.space
            && lhs.isSelectedSpace == rhs.isSelectedSpace
            && lhs.tabPromotionNamespace == rhs.tabPromotionNamespace
            && lhs.shortcuts === rhs.shortcuts && lhs.layoutDirection == rhs.layoutDirection
    }

    private var isInteractive: Bool {
        isSelectedSpace && contentPresentation == .interactive
    }

    /// How the window shows this Space's pages: as the person's, as the
    /// preview the pager draws while the person swipes to or from the Space,
    /// or not at all.
    private var pagePresentation: BrowserPagePresentation {
        if isInteractive { return .presented }
        return contentPresentation == .inactive ? .hidden : .preview
    }

    /// The tab the window shows in this Space.
    private var shownTab: TabStateModel? {
        model.browser.selectedTabID(in: space.id).flatMap { space.tabs.model($0) }
    }

    private var surfacePage: BrowserPage? {
        shownTab.flatMap { model.pages.surfacePage(for: $0.id, in: space) }
    }

    private var previewsStartPage: Bool {
        !isSelectedSpace && model.pages.requiresStartPageOnEntry(to: space)
    }

    private var pageSurfacePresentation: BrowserPageSurfacePresentation {
        if previewsStartPage {
            return .single(space: space, cardTabID: nil)
        }
        return BrowserPageSurfacePresentation(
            space: space,
            cards: model.browser.cards(in: space),
            hasEnteredSplitContent:
                isSelectedSpace && model.sidebarInteraction.sidebarReorderState.hasEnteredSplitContent,
            resolvedTarget: isSelectedSpace ? model.sidebarInteraction.sidebarReorderState.resolvedTarget : nil,
            presentsTrailingPanel: isSelectedSpace && model.extensionSidePanel.panel != nil
        )
    }

    var body: some View {
        let presentation = pageSurfacePresentation
        return surface(presentation)
            .environment(\.browserPagePresentationWindowID, model.windowState?.id)
            .environment(\.spaceContentIsInteractive, isInteractive)
            .environment(\.browserPagePresentation, pagePresentation)
            .allowsHitTesting(isInteractive)
            .accessibilityHidden(!isInteractive)
            .browserSplitContentDropZone(
                assignment: isSelectedSpace ? presentation.dropAssignment : nil,
                state: model.sidebarInteraction.sidebarReorderState
            )
            .environment(
                \.browserWebFocusRestorationGate,
                BrowserWebFocusRestorationGate(
                    browserChromeOwnsFocus: !isInteractive || !model.isWindowFocused
                        || model.chrome.isCommandPalettePresented,
                    pageChromeOwnsFocus: false))
    }

    @ViewBuilder
    private func surface(
        _ presentation: BrowserPageSurfacePresentation
    ) -> some View {
        if case .columns(let space, let members, let placeholderIndex) =
            presentation
        {
            BrowserSplitPageSurface(
                model: model,
                space: space,
                members: members,
                placeholderIndex: placeholderIndex,
                tabPromotionNamespace: tabPromotionNamespace,
                shortcuts: shortcuts
            )
        } else {
            BrowserRootDetailSurface(
                adjoinsLeadingSidebar: false,
                usesBorderlessFrame: true,
                isStartPage: previewsStartPage || shownTab?.surface == .startPage,
                hasActivePage: surfacePage != nil,
                completedNavigationCount: surfacePage?.completedNavigationCount ?? 0,
                hasSelectedSpace: true,
                handleWebContentInteraction: model.chrome.handleWebContentInteraction,
                content: Group {
                    BrowserDetailView(
                        presentation: presentation,
                        browser: model.browser,
                        pages: model.pages,
                        tabPromotionNamespace: tabPromotionNamespace,
                        startPageFocusRequest:
                            model.chrome.startPageFocusRequest,
                        isCommandPalettePresented:
                            model.chrome.isCommandPalettePresented,
                        commands: model.paletteRegistry(
                            windows: windows, layoutDirection: layoutDirection, shortcuts: shortcuts),
                        previewsStartPage: previewsStartPage
                    )
                }
            )
            // The lone tab on show is a card as far as a drag is concerned: it
            // is what a dropped tab would join, and the side of it the pointer
            // is on is which side of it the new card lands.
            .browserSplitDropCardFrame(
                tabID: isSelectedSpace ? presentation.singleCardTabID : nil,
                assignment: isSelectedSpace ? presentation.dropAssignment : nil,
                state: model.sidebarInteraction.sidebarReorderState
            )
        }
    }
}
