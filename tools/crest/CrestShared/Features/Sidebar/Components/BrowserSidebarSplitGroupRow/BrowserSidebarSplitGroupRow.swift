import SwiftUI

/// A split group as one sidebar row, on every shell: a grouped surface holding
/// the count affordance and one ordinary tab row per member.
///
/// The members are not a compact imitation of a tab row — they are
/// `BrowserSidebarTabRow`, the same view the rest of the list draws, so a split
/// reads as tabs that have been gathered rather than as a widget that replaced
/// them. The container carries what belongs to the group — presented, dragged,
/// dropped against, and the two ways a split ends — and each row carries what
/// belongs to its own tab. That division is what lets a group be one row to the
/// list while still letting a person focus, rename, or close one pane.
///
/// What differs between a pointer shell and a touch one is read from
/// `BrowserInteractionCapabilities` rather than from which target compiled the
/// file, so the two shells share this row instead of a resemblance.
struct BrowserSidebarSplitGroupRow: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    let groupID: UUID
    /// The members the sidebar shows in the row, in order.
    let members: [TabStateModel]
    let context: BrowserSidebarListContext

    @Environment(\.sidebarSpacePresentation) private var spacePresentation
    var body: some View {
        BrowserSidebarSplitGroupRowContent(
            configuration: configuration,
            interaction: interaction
        )
        .modifier(
            BrowserSidebarSplitGroupRowSurface(
                configuration: configuration
            )
        )
    }

    private var configuration: BrowserSidebarSplitGroupRowConfiguration {
        BrowserSidebarSplitGroupRowConfiguration(
            sidebarInteraction: sidebarInteraction,
            groupID: groupID,
            members: members,
            context: context,
            spacePresentation: spacePresentation
        )
    }

    private var interaction: BrowserSidebarSplitGroupRowInteractionContext {
        BrowserSidebarSplitGroupRowInteractionContext(activate: activate, closeSplit: closeSplit)
    }

    private func activate() {
        guard configuration.isCurrentAndAvailable,
            let memberID = configuration.focusedMemberID
                ?? configuration.members.first?.id
        else { return }
        context.select(memberID)
    }

    private func closeSplit() {
        guard configuration.canClose, configuration.isCurrentAndAvailable else { return }
        // Closing the second-to-last member dissolves the group through the
        // domain's survivor rule; the final close then takes an ordinary tab.
        for member in configuration.members {
            configuration.browser.closeTab(
                member.id,
                matching: configuration.assignment
            )
        }
    }

}

extension BrowserSidebarSplitGroupRow: @MainActor Equatable {
    /// Rows are equal when they stand for the same members in the same place,
    /// as SwiftUI compares a view's inputs: a list that redraws leaves them be.
    static func == (lhs: BrowserSidebarSplitGroupRow, rhs: BrowserSidebarSplitGroupRow) -> Bool {
        lhs.groupID == rhs.groupID && lhs.members.elementsEqual(rhs.members, by: ===) && lhs.context == rhs.context
    }
}
