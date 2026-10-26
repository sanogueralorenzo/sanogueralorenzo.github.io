import SwiftUI

/// The saved section's top level: its folders and unfiled tabs in the one
/// order the core publishes, so a tab can stay between sibling folders.
struct BrowserSavedTabsDropSection: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let context: BrowserSidebarListContext

    private var section: BrowserSidebarReorderSection {
        .tabs(placement: .saved, folderID: nil)
    }

    var body: some View {
        let list = context.space.sidebar.section(.saved)
        VStack(spacing: 0) {
            if context.capabilities.reservesReorderSectionZones {
                BrowserSidebarListRows(list: list, context: context).equatable()

                // Also the band an empty unfiled run draws its insertion line
                // in: it sits directly below the folder groups, where that
                // run's first row would appear.
                BrowserSavedTabsEndDropTarget(context: context)
                    .browserSidebarReorderSectionIndicator(
                        section,
                        state: sidebarInteraction.sidebarReorderState
                    )
            } else {
                BrowserSidebarListRows(list: list, context: context)
                    .equatable()
                    .browserSidebarReorderSectionIndicator(
                        section,
                        state: sidebarInteraction.sidebarReorderState
                    )
            }
        }
        .contentShape(.rect)
        .browserSidebarReorderZone(
            .section(section),
            state: sidebarInteraction.sidebarReorderState,
            minimumHeight: metrics.savedSectionEndBandHeight
        )
        .modifier(
            BrowserSidebarSectionReservation(
                section: section,
                state: sidebarInteraction.sidebarReorderState,
                capabilities: context.capabilities
            )
        )
        .accessibilityHint("Drop a tab here to save it")
    }

    private var metrics: BrowserSidebarTabListMetrics {
        context.capabilities.tabListMetrics
    }
}
