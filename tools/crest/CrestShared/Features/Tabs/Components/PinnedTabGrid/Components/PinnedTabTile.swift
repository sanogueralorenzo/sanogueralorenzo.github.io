import SwiftUI

/// One pinned tab's tile in the grid.
///
/// It reads its own tab, whether its window shows it, whether it is selected
/// for tab actions and whether it holds a page, so a change to any of them
/// redraws this tile and no other.
struct PinnedTabTile: View {
    let tab: TabStateModel
    let grid: PinnedTabGrid
    let reorder: BrowserSidebarReorderContext?
    @State private var renameRequest: BrowserTabRuntimeAssignment?
    @State private var draftTitle = ""
    @FocusState private var isTitleFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var context: BrowserSidebarListContext? { grid.context }
    private var assignment: BrowserSpaceRuntimeAssignment { grid.assignment }

    var body: some View {
        let runtimeAssignment = self.runtimeAssignment
        let isSelected = grid.window?.shownTabIDs.contains(tab.id) ?? (tab.id == grid.selectedTabID)
        let loaded = context?.isLoaded(tab.id) ?? true
        let isShared = context?.isSharedAsTab(tab.id) ?? false
        let multiSelection = context?.browser.tabMultiSelection
        tile(isSelected: isSelected, loaded: loaded)
            .browserPinnedTabPromotionDestination(
                id: BrowserTabPromotionID.value(for: tab.id),
                in: grid.promotionNamespace,
                anchor: BrowserPinnedTabPromotionAnchor(
                    hasNamespace: grid.promotionNamespace != nil,
                    isTransitionSource: isSelected,
                    capabilities: grid.capabilities
                )
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tab.shownTitle)
            .accessibilityValue(
                isShared
                    ? Text(
                        "\(BrowserChromeAccessibility.tabValue(isLoaded: loaded)), Shared",
                        comment:
                            "Accessibility value of a pinned tab another page shares; the value is its loaded state.")
                    : Text(BrowserChromeAccessibility.tabValue(isLoaded: loaded))
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .help(tab.shownTitle)
            .modifier(
                BrowserTabSelectionAccessibility(
                    tabID: tab.id, spaceID: assignment.spaceID, browser: context?.browser,
                    isActive: isSelected, isLoaded: loaded)
            )
            .modifier(
                BrowserTabSelectionTarget(
                    tabID: tab.id, browser: context?.browser, assignment: assignment,
                    isEnabled: !isRenaming && (context?.isCurrent(assignment) ?? false))
            )
            .phaseAnimator(
                [0.0, -4.0, 4.0, -3.0, 3.0, 0.0],
                trigger: multiSelection?.pinnedRejectionGeneration ?? 0
            ) { content, offset in
                content.offset(
                    x: !reduceMotion && multiSelection?.rejectedPinnedIDs.contains(tab.id) == true
                        ? offset : 0)
            } animation: { _ in
                .linear(duration: 0.055)
            }
            .modifier(
                PinnedTabDragModifier(
                    tab: tab,
                    favicons: grid.favicons,
                    assignment: assignment,
                    dragState: grid.dragState,
                    reorder: isRenaming ? nil : reorder
                )
            )
            .contextMenu {
                if grid.capabilities.supportsOrganization, let context {
                    PinnedTabOrganizationMenu(
                        tab: tab,
                        context: context,
                        assignment: runtimeAssignment,
                        dragState: grid.dragState,
                        renameTab: beginRenaming
                    )
                }
            }
            .modifier(BrowserTabStatusBadgeHost(tab: statusSource))
            .animation(
                CrestMotion.contentState.unlessReducingMotion(reduceMotion),
                value: loaded
            )
            .onChange(of: isTitleFocused) { _, focused in
                if !focused, isRenaming { commitTitle() }
            }
            .onChange(of: isCurrentAndAvailable) { _, isAvailable in
                if !isAvailable { cancelTitleEditing() }
            }
            .onChange(of: runtimeAssignment) { _, _ in cancelTitleEditing() }
            .crestCollectionItemTransition()
    }

    @ViewBuilder
    private func tile(isSelected: Bool, loaded: Bool) -> some View {
        if isRenaming {
            BrowserSidebarTabRenameField(
                tab: tab, favicons: grid.favicons, profileID: assignment.profileID,
                metrics: grid.capabilities.tabRowMetrics,
                draftTitle: $draftTitle, isTitleFocused: $isTitleFocused,
                commitTitle: commitTitle, cancelTitleEditing: cancelTitleEditing
            )
            .padding(.horizontal, grid.capabilities.tabRowMetrics.contentLeadingInset)
            .frame(height: BrowserSidebarDensity(1).pinHeight(touch: grid.capabilities.supportsTouch))
            .crestInteractiveSurface(isSelected: isSelected, isHovering: false)
        } else {
            PinnedTabSelectionButton(
                tab: tab,
                favicons: grid.favicons,
                profileID: assignment.profileID,
                isSelected: isSelected,
                isLoaded: loaded,
                siteTheme: tab.iconMode.followsPage
                    ? (grid.siteThemeAccent(runtimeAssignment) ?? tab.iconTint)
                    : tab.iconTint,
                select: {
                    guard isCurrentAndAvailable else { return }
                    // The touch-up that ends a lift also reaches this button;
                    // opening the tile that was just dragged is not a select.
                    if let reorder, reorder.state.suppressesActivation { return }
                    grid.select(runtimeAssignment)
                },
                isMultiSelected: context.map { BrowserSidebarSelection.showsSelected(.tab(tab.id), in: $0) } ?? false,

                statusSource: statusSource,
                returnToSavedURL: canReturnToSavedAddress
                    ? {
                        guard isCurrentAndAvailable else { return }
                        context?.restoreSavedLocation?(tab.id)
                    } : nil

            )
        }
    }

    private var isRenaming: Bool {
        renameRequest == runtimeAssignment && isCurrentAndAvailable
    }

    private var canReturnToSavedAddress: Bool {
        guard let context else { return false }
        return BrowserSidebarTabRowConfiguration(
            tab: tab, context: context, isSelected: true, isLoaded: context.isLoaded(tab.id)
        ).canReturnToSavedAddress
    }

    private func beginRenaming() {
        guard isCurrentAndAvailable else { return }
        draftTitle = tab.shownTitle
        renameRequest = runtimeAssignment
        Task { @MainActor in isTitleFocused = true }
    }

    private func commitTitle() {
        guard isRenaming, let context else { return }
        renameRequest = nil
        context.browser.setTabCustomTitle(draftTitle, for: tab.id, matching: assignment)
    }

    private func cancelTitleEditing() {
        renameRequest = nil
        isTitleFocused = false
    }

    private var runtimeAssignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: assignment.spaceID, profileID: assignment.profileID)
    }

    private var isCurrentAndAvailable: Bool {
        context?.isTabCurrent(runtimeAssignment) ?? false
    }

    /// The tab's page as its status badge reads it and acts on it.
    private var statusSource: BrowserTabStatusSource? {
        guard let context else { return nil }
        return BrowserTabStatusSource(tabID: tab.id, context: context, canAct: { isCurrentAndAvailable })
    }
}
