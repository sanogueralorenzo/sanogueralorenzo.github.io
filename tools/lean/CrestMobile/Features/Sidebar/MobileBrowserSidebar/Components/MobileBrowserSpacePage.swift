import SwiftUI

/// One Space's sidebar on the compact shell: the pinned grid, the Space header,
/// and the scrolling tab list.
///
/// Everything here is composition and binding. The sections and the list are the
/// shared ones; what this shell adds is its own scrolling chrome, the drop feed
/// that covers the whole sidebar, and the page-facing closures only a single
/// compact page can answer.
struct MobileBrowserSpacePage: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    let space: SpaceModel
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let capabilities: BrowserInteractionCapabilities
    let tabPromotionNamespace: Namespace.ID
    let selectTab: (UUID) -> Void
    let openNewTab: () -> Void
    let showHistory: () -> Void
    let showSettings: () -> Void
    let closePrivateBrowsing: () -> Void
    let compactPageIsFullyPresented: Bool

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let listContext {
            content(listContext)
        }
    }

    private func content(_ listContext: BrowserSidebarListContext) -> some View {
        VStack(spacing: 0) {
            // The bounded pinned grid keeps its intrinsic height. Compressing
            // its wrapper when the keyboard appears lets fixed-height tiles
            // overflow upward into the Space picker.
            BrowserPinnedTabsDropSection(context: listContext)
                .equatable()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, BrowserSidebarMetrics.layerInset)
                .padding(.vertical, 10)

            BrowserSpaceHeader(
                space: space,
                isPrivateBrowsing: browser.isPrivateBrowsing,
                capabilities: capabilities,
                actions: BrowserSpaceHeaderActions(
                    openNewTab: openNewTab,
                    openNewWindow: { openWindow(value: MobileWindowRequest()) },
                    createFolder: beginCreatingFolder,
                    showHistory: showHistory,
                    closePrivateBrowsing: closePrivateBrowsing,
                    showSettings: showSettings
                )
            )

            MobileBrowserSpaceTabListScroll(
                context: listContext,
                compactPageIsFullyPresented: compactPageIsFullyPresented,
                openNewTab: openNewTab
            ) {
                BrowserSidebarTabList(context: listContext, openNewTab: openNewTabIfAvailable)
                    .equatable()
            }
        }
        .modifier(
            MobileBrowserReorderDropFeed(
                browser: browser
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            BrowserSpaceAccessibilityID.sidebar(space.id)
        )
        .accessibilityLabel("\(space.settings.name) Space sidebar")
    }

    /// The Space and this window as the read model keeps them, and what the
    /// rows act through. Every section anchors its rows' pages here.
    private var listContext: BrowserSidebarListContext? {
        guard let window = browser.windowModel else { return nil }
        return BrowserSidebarListContext(
            space: space, window: window, favicons: browser.core.state.favicons, browser: browser,
            pageAccess: pageAccess, tabActions: tabActions, capabilities: capabilities,
            promotionNamespaces: [
                .pinned: tabPromotionNamespace, .saved: tabPromotionNamespace, .current: tabPromotionNamespace,
            ],
            select: selectTab, restoreSavedLocation: restoreSavedLocation)
    }

    private var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(pages: pages, browser: browser)
    }

    private var tabActions: BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: assignment,
            browser: browser, reorderState: sidebarInteraction.sidebarReorderState, syncPagesAfterMutation: {}
        )
    }

    private func openNewTabIfAvailable() {
        guard isCurrentAndAvailable else { return }
        openNewTab()
    }

    private func restoreSavedLocation(_ tabID: UUID) {
        guard isCurrentAndAvailable else { return }
        MobileSavedLocationRestoreAction(
            browser: browser,
            pages: pages,
            selectTab: selectTab
        ).perform(
            BrowserTabRuntimeAssignment(
                tabID: tabID,
                spaceID: space.id,
                profileID: space.profileID
            )
        )
    }

    private func beginCreatingFolder() {
        guard isCurrentAndAvailable,
            let folderID = browser.addFolder(matching: assignment)
        else { return }
        sidebarInteraction.editingFolderRequest = BrowserFolderRuntimeAssignment(
            folderID: folderID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }

    private var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: space)
    }

    private var isCurrentAndAvailable: Bool {
        browser.selectedAvailableSpace(matching: assignment) != nil
    }
}
