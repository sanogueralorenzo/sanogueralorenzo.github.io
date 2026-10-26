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

    /// Names follow the current tab titles, in their sidebar order.
    var shownTitle: String {
        members.isEmpty ? String(localized: "Split View") : members.map(\.displayTitle).joined(separator: " / ")
    }

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
            state: sidebarInteraction.sidebarReorderState
        )
    }

    /// Inactive pages retain their normal control appearance while commands
    /// remain guarded by the live selected Space below.
    var isAvailableForDisplay: Bool {
        guard let spacePresentation else { return isCurrentAndAvailable }
        return spacePresentation.isAvailable(matching: assignment) && holdsMembers
    }

    var isCurrentAndAvailable: Bool {
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

struct BrowserSidebarSplitGroupRowInteractionContext {
    let activate: () -> Void
    let closeSplit: @MainActor () -> Void
}
