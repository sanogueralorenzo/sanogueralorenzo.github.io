import SwiftUI

/// One tab in the sidebar, on every shell.
///
/// The row owns the state a tab row has to keep between events — hover, the
/// rename in flight, the height a drop indicator sizes itself against — and
/// hands everything else to `BrowserSidebarTabRowConfiguration`. What differs
/// between a pointer shell and a touch one is read from
/// `BrowserInteractionCapabilities` rather than from which target compiled
/// the file, so the two shells share this row instead of a resemblance.
struct BrowserSidebarTabRow: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let tab: TabStateModel
    let context: BrowserSidebarListContext
    /// Set by the container that nests this row inside a split group. See
    /// `BrowserSidebarTabRowConfiguration.isSplitGroupMember`.
    var isSplitGroupMember = false
    /// The row a drop below this one would land in front of. Only read where
    /// the shell draws its insertion line on the rows themselves.
    var followingTabID: UUID? = nil

    @Environment(\.sidebarSpacePresentation) private var spacePresentation
    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var dropTargetHeight = CrestLayout.sidebarRowHeight
    @State private var renameRequest: BrowserTabRuntimeAssignment?
    @State private var iconRequest: BrowserTabRuntimeAssignment?
    @State private var draftTitle = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        let configuration = self.configuration
        let interaction = self.interaction
        BrowserSidebarTabRowContent(
            configuration: configuration,
            interaction: interaction
        )
        .modifier(
            BrowserSidebarTabRowSurface(
                configuration: configuration,
                interaction: interaction
            )
        )
        .modifier(
            BrowserTabStatusBadgeHost(
                tab: BrowserTabStatusSource(
                    tabID: tab.id, context: context, canAct: { configuration.isCurrentAndUnlocked }))
        )
        .environment(\.browserInteractionCapabilities, context.capabilities)
        .onChange(of: runtimeAssignment) { _, assignment in
            guard renameRequest != assignment else { return }
            cancelTitleEditing()
            iconRequest = nil
        }
        .modifier(
            SidebarSpaceRoleCleanupModifier(
                isAvailable: configuration.isAvailableForDisplay,
                hasPendingActions: renameRequest != nil || iconRequest != nil,
                cancel: {
                    cancelTitleEditing()
                    iconRequest = nil
                }
            )
        )
    }

    /// What the row draws from: its own tab, whether its window shows that
    /// tab, and whether the tab holds a page.
    private var configuration: BrowserSidebarTabRowConfiguration {
        BrowserSidebarTabRowConfiguration(
            tab: tab,
            context: context,
            isSelected: context.window.shownTabIDs.contains(tab.id),
            isLoaded: context.isLoaded(tab.id),
            isSplitGroupMember: isSplitGroupMember,
            followingTabID: followingTabID,
            spacePresentation: spacePresentation
        )
    }

    private var interaction: BrowserSidebarTabRowInteractionContext {
        BrowserSidebarTabRowInteractionContext(
            isHovering: $isHovering,
            isDropTargeted: $isDropTargeted,
            dropTargetHeight: $dropTargetHeight,
            isRenaming: isRenaming,
            draftTitle: $draftTitle,
            isTitleFocused: $isTitleFocused,
            isChoosingIcon: iconPresentation,
            activate: activate,
            beginRenaming: beginRenaming,
            beginChangingIcon: beginChangingIcon,
            setEmojiIcon: setRequestedTabEmoji,
            resetIcon: clearRequestedTabIcon,
            commitTitle: commitTitle,
            cancelTitleEditing: cancelTitleEditing,
            dismissFromAuxiliaryClick: dismissFromAuxiliaryClick
        )
    }

    private func activate() {
        guard configuration.isCurrentAndUnlocked else { return }
        // The lift and this button recognise simultaneously — deliberately, or
        // the button would suppress the lift — so the release that ends a
        // reorder also arrives here. Reject it rather than opening the tab that
        // was just moved.
        guard !sidebarInteraction.sidebarReorderState.suppressesActivation else { return }
        context.select(tab.id)
    }

    private func beginRenaming() {
        guard configuration.isCurrentAndUnlocked else { return }
        draftTitle = tab.shownTitle
        renameRequest = runtimeAssignment
        Task { @MainActor in
            isTitleFocused = true
        }
    }

    private func beginChangingIcon() {
        guard configuration.isCurrentAndUnlocked else { return }
        iconRequest = runtimeAssignment
    }

    private var iconPresentation: Binding<Bool> {
        Binding {
            iconRequest == runtimeAssignment
                && configuration.isAvailableForDisplay
        } set: { isPresented in
            if isPresented {
                beginChangingIcon()
            } else {
                iconRequest = nil
            }
        }
    }

    private func setRequestedTabEmoji(_ emoji: String) {
        guard let request = iconRequest,
            request == runtimeAssignment,
            configuration.isCurrentAndUnlocked
        else { return }
        context.browser.setTabEmojiIcon(
            emoji,
            for: request.tabID,
            matching: configuration.assignment
        )
    }

    private func clearRequestedTabIcon() {
        guard let request = iconRequest,
            request == runtimeAssignment,
            configuration.isCurrentAndUnlocked
        else { return }
        context.browser.clearTabIcon(
            for: request.tabID,
            matching: configuration.assignment
        )
    }

    private func commitTitle() {
        guard let request = renameRequest else { return }
        renameRequest = nil
        guard request == runtimeAssignment,
            configuration.isCurrentAndUnlocked
        else { return }
        context.browser.setTabCustomTitle(
            draftTitle,
            for: request.tabID,
            matching: BrowserSpaceRuntimeAssignment(
                spaceID: request.spaceID,
                profileID: request.profileID
            )
        )
    }

    private func cancelTitleEditing() {
        guard renameRequest != nil else { return }
        draftTitle = tab.shownTitle
        renameRequest = nil
    }

    private func dismissFromAuxiliaryClick() {
        let configuration = self.configuration
        guard configuration.isCurrentAndUnlocked else { return }
        BrowserTabMiddleClickAction(for: tab.placement).perform(on: configuration)
    }

    private var isRenaming: Bool {
        renameRequest == runtimeAssignment
            && configuration.isAvailableForDisplay
    }

    private var runtimeAssignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: context.space.id, profileID: context.space.profileID)
    }
}

extension BrowserSidebarTabRow: @MainActor Equatable {
    /// Rows are equal when they stand for the same tab in the same place, as
    /// SwiftUI compares a view's inputs: a list that redraws leaves them be.
    static func == (lhs: BrowserSidebarTabRow, rhs: BrowserSidebarTabRow) -> Bool {
        lhs.tab === rhs.tab && lhs.context == rhs.context && lhs.isSplitGroupMember == rhs.isSplitGroupMember
            && lhs.followingTabID == rhs.followingTabID
    }
}
