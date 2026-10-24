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
    @Binding var iconRequest: BrowserTabRuntimeAssignment?
    let renameTab: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var context: BrowserSidebarListContext? { grid.context }
    private var assignment: BrowserSpaceRuntimeAssignment { grid.assignment }

    var body: some View {
        let runtimeAssignment = self.runtimeAssignment
        let isSelected = grid.window?.shownTabIDs.contains(tab.id) ?? (tab.id == grid.selectedTabID)
        let loaded = context?.isLoaded(tab.id) ?? true
        let isShared = context?.isSharedAsTab(tab.id) ?? false
        let multiSelection = context?.browser.tabMultiSelection
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
                guard isCurrentAndUnlocked else { return }
                // The touch-up that ends a lift also reaches this button;
                // opening the tile that was just dragged is not a select.
                if let reorder, reorder.state.suppressesActivation { return }
                grid.select(runtimeAssignment)
            },
            isMultiSelected: context.map { BrowserSidebarSelection.showsSelected(.tab(tab.id), in: $0) } ?? false,
            branding: context.map(\.space.settings.look),
            statusSource: statusSource,
            iconCustomization: iconCustomization
        )
        .browserPinnedTabPromotionDestination(
            id: BrowserTabPromotionID.value(for: tab.id),
            in: grid.promotionNamespace,
            anchor: BrowserPinnedTabPromotionAnchor(
                hasNamespace: grid.promotionNamespace != nil,
                isTransitionSource: isSelected,
                capabilities: grid.capabilities
            )
        )
        .accessibilityLabel(tab.shownTitle)
        .accessibilityValue(
            isShared
                ? Text(
                    "\(BrowserChromeAccessibility.tabValue(isLoaded: loaded)), Shared",
                    comment: "Accessibility value of a pinned tab another page shares; the value is its loaded state.")
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
                isEnabled: context?.isCurrent(assignment) ?? false)
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
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                guard tab.placement == .pinned, tab.supportsSavedLocationEditing, isCurrentAndUnlocked else {
                    return
                }
                context?.restoreSavedLocation?(tab.id)
            }
        )
        .browserPinnedTabMiddleClick {
            guard context?.isLoaded(tab.id) == true, isCurrentAndUnlocked else { return }
            context?.unload(tab.id)
        }
        .modifier(
            PinnedTabDragModifier(
                tab: tab,
                favicons: grid.favicons,
                assignment: assignment,
                dragState: grid.dragState,
                reorder: reorder
            )
        )
        .contextMenu {
            if grid.capabilities.supportsOrganization, let context {
                PinnedTabOrganizationMenu(
                    tab: tab,
                    context: context,
                    assignment: runtimeAssignment,
                    isLoaded: loaded,
                    dragState: grid.dragState,
                    renameTab: renameTab,
                    changeIcon: beginChangingIcon
                )
            }
        }
        .modifier(BrowserTabStatusBadgeHost(tab: statusSource, anchor: .tile))
        .animation(
            CrestMotion.contentState.unlessReducingMotion(reduceMotion),
            value: loaded
        )
        .crestCollectionItemTransition()
    }

    private var runtimeAssignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: assignment.spaceID, profileID: assignment.profileID)
    }

    private var isCurrentAndUnlocked: Bool {
        context?.isTabCurrent(runtimeAssignment) ?? false
    }

    /// The tab's page as its status badge reads it and acts on it.
    private var statusSource: BrowserTabStatusSource? {
        guard let context else { return nil }
        return BrowserTabStatusSource(tabID: tab.id, context: context, canAct: { isCurrentAndUnlocked })
    }

    private var iconActions: BrowserTabOrganizationAction? {
        guard let context else { return nil }
        return BrowserTabOrganizationAction(browser: context.browser, spaceAccess: context.spaceAccess)
    }

    private var isIconRequestLive: Bool {
        guard iconRequest == runtimeAssignment, grid.capabilities.supportsOrganization else { return false }
        return iconActions?.canCustomizePinnedIcon(for: runtimeAssignment) == true
    }

    private func beginChangingIcon() {
        guard grid.capabilities.supportsOrganization,
            iconActions?.canCustomizePinnedIcon(for: runtimeAssignment) == true
        else { return }
        iconRequest = runtimeAssignment
    }

    private var iconCustomization: BrowserIconCustomizationPresentation {
        let request = runtimeAssignment
        return BrowserIconCustomizationPresentation(
            isPresented: Binding(
                get: { isIconRequestLive },
                set: { isPresented in
                    if isPresented {
                        beginChangingIcon()
                    } else if iconRequest == request {
                        iconRequest = nil
                    }
                }
            ),
            title: "Tab Icon",
            currentEmoji: tab.emojiIcon,
            // Reset applies to explicit icon overrides.
            showsReset: !tab.iconMode.followsPage,
            resetTitle: "Use Website Icon",
            setEmoji: { emoji in
                guard isIconRequestLive else { return }
                iconActions?.setPinnedTabEmoji(emoji, for: request)
            },
            reset: {
                guard isIconRequestLive else { return }
                iconActions?.clearPinnedTabIcon(for: request)
            }
        )
    }
}
