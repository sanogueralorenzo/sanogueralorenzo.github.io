import SwiftUI

/// The insertion lines a group draws while a tab is being dragged over the
/// list.
///
/// The container owns both of them for the whole run, because the group is one
/// row to the list: the line above lands in front of the first member and the
/// line below skips past the last, so a drop can never be aimed between two
/// panes of a split. Only shells that put the feedback on the rows themselves
/// apply these; where the section's own zone carries the whole answer, the
/// group stays quiet and this modifier steps aside entirely.
struct BrowserSidebarSplitGroupRowDropIndicators: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserSidebarSplitGroupRowConfiguration

    @ViewBuilder
    func body(content: Content) -> some View {
        if configuration.capabilities.showsRowDropIndicators {
            content
                .overlay(alignment: .top) {
                    BrowserTabDropIndicator(
                        location: configuration.beforeDropLocation,
                        dragState: sidebarInteraction.tabDragState,
                        isTargeted: false
                    )
                }
                .overlay(alignment: .bottom) { trailingIndicator }
        } else {
            content
        }
    }

    /// The last row in a run owns the line below it: no row follows to draw
    /// the same seam from its own top edge.
    @ViewBuilder
    private var trailingIndicator: some View {
        // A row owns the indicator after it only while no visible row follows it.
        if !configuration.hasVisibleFollowingRow {
            BrowserTabDropIndicator(
                location: configuration.afterDropLocation,
                dragState: sidebarInteraction.tabDragState,
                isTargeted: false
            )
        }
    }
}
