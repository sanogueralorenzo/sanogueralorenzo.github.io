import SwiftUI

/// The Space's current tabs as one drop section, on every shell.
///
/// New Tab follows this section, so drop indicators and insertion gaps stay
/// with the tab rows rather than covering the action.
struct BrowserCurrentTabsDropSection: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let context: BrowserSidebarListContext

    private var section: BrowserSidebarReorderSection {
        .tabs(placement: .current, folderID: nil)
    }

    var body: some View {
        let list = context.space.sidebar.section(.current)
        if !list.isEmpty || isDragging {
            sectionContent(list: list)
        }
    }

    private var isDragging: Bool {
        sidebarInteraction.sidebarReorderState.hasLiftInFlight
            || sidebarInteraction.tabDragState.item != nil || sidebarInteraction.folderDragState.item != nil
    }

    private func sectionContent(list: SidebarListModel) -> some View {
        VStack(spacing: 0) {
            if context.capabilities.reservesReorderSectionZones {
                BrowserSidebarListRows(list: list, context: context).equatable()

                // Also the band a cleared list draws its insertion line in: it
                // sits above New Tab, where the first current tab would appear.
                BrowserCurrentTabsEndDropTarget(context: context)
                    .browserSidebarReorderSectionIndicator(
                        section,
                        state: sidebarInteraction.sidebarReorderState
                    )
            } else {
                BrowserSidebarListRows(list: list, context: context) { items in
                    // A cleared list has no row to draw the seam on, so it
                    // keeps a band above New Tab for the line to stand
                    // in.
                    if items.isEmpty {
                        Color.clear
                            .frame(height: metrics.sectionEndBandHeight)
                            .contentShape(.rect)
                            .accessibilityHidden(true)
                    }
                }
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
            state: sidebarInteraction.sidebarReorderState
        )
        .modifier(
            BrowserSidebarSectionReservation(
                section: section,
                state: sidebarInteraction.sidebarReorderState,
                capabilities: context.capabilities
            )
        )
        .accessibilityHint("Drop a tab here to make it a current tab")
    }

    private var metrics: BrowserSidebarTabListMetrics {
        context.capabilities.tabListMetrics
    }
}
