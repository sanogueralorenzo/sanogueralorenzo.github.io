import SwiftUI

/// Everything a stacked split-group row is told, and the answers that follow
/// from it.
///
/// Gathered once so the container's parts stay small and the group's rules —
/// which member is focused, where a drop beside the run lands, whether the
/// Space will accept a mutation at all — live in one place rather than in each
/// of them.
@MainActor
struct BrowserSidebarSplitGroupRowConfiguration {
    // MARK: - Variables

    let sidebarInteraction: BrowserSidebarInteractionState
    let groupID: UUID
    let members: [TabStateModel]
    let context: BrowserSidebarListContext
    /// The Space the row was drawn for, as it stood then. An action checks it
    /// against the live Space, so a row drawn before a profile was replaced
    /// can never act for the replacement.
    let assignment: BrowserSpaceRuntimeAssignment
    /// The member the window shows, and the only row that takes the selection
    /// accent. `nil` while the group is not presented at all.
    let focusedMemberID: UUID?
    var spacePresentation: SidebarSpacePresentation? = nil

    var spaceID: UUID { assignment.spaceID }
    var profileID: UUID { assignment.profileID }
    var browser: BrowserStore { context.browser }
    var spaceAccess: BrowserSpaceAccessController { context.spaceAccess }
    var capabilities: BrowserInteractionCapabilities { context.capabilities }

    var metrics: BrowserSidebarSplitGroupRowMetrics {
        capabilities.splitGroupRowMetrics
    }

    /// The member rows' own profile, which the container reads for the header
    /// inset it borrows rather than chooses.
    var tabRowMetrics: BrowserSidebarTabRowMetrics {
        capabilities.tabRowMetrics
    }

    /// Puts the header's glyph in the same column as the member rows'
    /// favicons: a member carries this same leading inset, and both sit inside
    /// the container's padding.
    var headerLeadingInset: CGFloat {
        tabRowMetrics.contentLeadingInset
    }

    var runtimeAssignment: BrowserSplitGroupRuntimeAssignment {
        BrowserSplitGroupRuntimeAssignment(
            groupID: groupID,
            spaceID: spaceID,
            profileID: profileID
        )
    }

    /// What a person chose for the split, as the core resolved it. Reading it
    /// observes the Space's splits.
    var choices: SplitGroupState {
        context.space.splitGroups.first { $0.id == groupID } ?? .unchosen(groupID)
    }

    var shownTitle: String { choices.shownTitle }
    var emojiIcon: String? { choices.displayEmojiIcon }
    var tint: BrandColor? { choices.tint }

    /// Selecting any member presents the whole split, so the container reads as
    /// presented whenever the window shows one of its members.
    var isPresented: Bool { focusedMemberID != nil }

    func isFocused(_ member: TabStateModel) -> Bool {
        member.id == focusedMemberID
    }

    /// The run is uniform by construction — the normalizer clears any member
    /// whose placement or folder drifts from the head's — so the head answers
    /// for the whole group.
    var placement: TabPlacement {
        members.first?.placement ?? .current
    }

    var folderID: UUID? {
        members.first?.folderID
    }

    /// A split of open tabs closes; one the session keeps does not.
    var canClose: Bool { !placement.isDurable }

    var dragItem: BrowserSplitGroupDragItem {
        BrowserSplitGroupDragItem(
            groupID: groupID,
            spaceID: spaceID,
            profileID: profileID,
            memberTabIDs: members.map(\.id)
        )
    }

    var reorderContext: BrowserSidebarReorderContext {
        BrowserSidebarReorderContext(
            browser: browser,
            spaceAccess: spaceAccess,
            state: sidebarInteraction.sidebarReorderState
        )
    }

    /// Inactive pages retain their normal control appearance while commands
    /// remain guarded by the live selected Space below.
    var isAvailableForDisplay: Bool {
        guard let spacePresentation else { return isCurrentAndUnlocked }
        return spacePresentation.isAvailable(matching: assignment) && holdsMembers
    }

    /// Every mutation this row offers is refused unless the window shows the
    /// Space the row was drawn for, unlocked, and the Space still holds the
    /// group.
    var isCurrentAndUnlocked: Bool {
        context.isCurrent(assignment) && holdsMembers
    }

    private var holdsMembers: Bool {
        members.contains { context.space.tabs.contains($0.id) }
    }

    // MARK: - Initializers

    init(
        sidebarInteraction: BrowserSidebarInteractionState, groupID: UUID, members: [TabStateModel],
        context: BrowserSidebarListContext, spacePresentation: SidebarSpacePresentation?
    ) {
        self.sidebarInteraction = sidebarInteraction
        self.groupID = groupID
        self.members = members
        self.context = context
        assignment = context.assignment
        focusedMemberID = members.first { context.window.shownTabIDs.contains($0.id) }?.id
        self.spacePresentation = spacePresentation
    }
}

struct BrowserSplitGroupRuntimeAssignment: Equatable, Sendable {
    let groupID: UUID
    let spaceID: UUID
    let profileID: UUID

    var spaceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
    }
}

struct BrowserSidebarSplitGroupRowInteractionContext {
    let isRenaming: Bool
    let draftTitle: Binding<String>
    let isTitleFocused: FocusState<Bool>.Binding
    let isChoosingIcon: Binding<Bool>
    let isChoosingTint: Binding<Bool>
    let tint: Binding<BrandColor>
    let activate: () -> Void
    let closeSplit: @MainActor () -> Void
    let beginRenaming: () -> Void
    let beginChangingIcon: () -> Void
    let beginChangingTint: () -> Void
    let setEmojiIcon: (String) -> Void
    let resetIcon: () -> Void
    let commitTitle: () -> Void
    let cancelTitleEditing: () -> Void
    let resetTint: () -> Void
}
