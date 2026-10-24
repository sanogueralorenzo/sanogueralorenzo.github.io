import SwiftUI

/// The insertion lines a row draws while a tab is being dragged over the list.
///
/// Only shells that put the feedback on the rows themselves apply these; where
/// the section's own zone carries the whole answer — or where the row is a
/// split group's member and its container owns the run's anchors — the row
/// stays quiet and this modifier steps aside entirely.
struct BrowserSidebarTabRowDropIndicators: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserSidebarTabRowConfiguration
    let isDropTargeted: Bool
    @Binding var dropTargetHeight: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if configuration.showsDropIndicators {
            content
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newHeight in
                    dropTargetHeight = newHeight
                }
                .overlay(alignment: .top) {
                    BrowserTabDropIndicator(
                        location: configuration.beforeDropLocation,
                        dragState: sidebarInteraction.tabDragState,
                        isTargeted: isDropTargeted
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
                isTargeted: isDropTargeted
            )
        }
    }
}
