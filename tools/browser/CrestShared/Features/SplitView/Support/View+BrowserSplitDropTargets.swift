import SwiftUI

extension View {
    /// Offers this region as the place a dragged sidebar tab becomes a card.
    func browserSplitContentDropZone(
        assignment: BrowserSpaceRuntimeAssignment?,
        state: BrowserSidebarReorderState
    ) -> some View {
        modifier(
            BrowserSplitContentDropZoneModifier(
                assignment: assignment,
                state: state
            )
        )
    }

    /// Reports this region as one presented card of `assignment`'s Space, so a
    /// drop resolves against it and against no other Space's cards.
    func browserSplitDropCardFrame(
        tabID: UUID?,
        assignment: BrowserSpaceRuntimeAssignment?,
        state: BrowserSidebarReorderState
    ) -> some View {
        modifier(
            BrowserSplitDropCardFrameModifier(
                tabID: tabID,
                assignment: assignment,
                state: state
            )
        )
    }
}
