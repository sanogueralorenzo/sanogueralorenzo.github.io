import SwiftUI

/// The landing band the unfiled saved run keeps at its end.
///
/// It matches the current run's band: a shell that reserves section zones for
/// imprecise input needs somewhere to aim past the last row, and an empty
/// unfiled run needs a region at all. It is also the place a dragged folder
/// lands beside the last root folder rather than inside it.
struct BrowserSavedTabsEndDropTarget: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    let context: BrowserSidebarListContext

    var body: some View {
        Color.clear
            .frame(height: bandHeight)
            .contentShape(.rect)
            .accessibilityHidden(true)
    }

    private var bandHeight: CGFloat {
        let isDragging =
            sidebarInteraction.sidebarReorderState.hasLiftInFlight
            || sidebarInteraction.tabDragState.item != nil || sidebarInteraction.folderDragState.item != nil
        return isDragging ? context.capabilities.tabListMetrics.savedSectionEndBandHeight : 0
    }

}
