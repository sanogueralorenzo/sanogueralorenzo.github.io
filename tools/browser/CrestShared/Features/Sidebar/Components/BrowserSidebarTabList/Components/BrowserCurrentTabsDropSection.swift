import SwiftUI

/// The Space's current tabs as one drop section, on every shell: the new-tab row
/// and the run of rows below it.
///
/// The current tabs are a run of their own inside this section's zone. They
/// start below the new-tab row, which is where a cleared list has to show that
/// it will still take a drop.
struct BrowserCurrentTabsDropSection: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let context: BrowserSidebarListContext
    let openNewTab: () -> Void

    private var section: BrowserSidebarReorderSection {
        .tabs(placement: .current, folderID: nil)
    }

    var body: some View {
        let list = context.space.sidebar.section(.current)
        VStack(spacing: 0) {
            BrowserNewTabRow(capabilities: context.capabilities, action: openNewTab)

            if context.capabilities.showsRowDropIndicators {
                BrowserSidebarListRows(list: list, context: context).equatable()

                // Also the band a cleared list draws its insertion line in: it
                // sits directly below the new-tab row, where the first current
                // tab would appear.
                BrowserCurrentTabsEndDropTarget(list: list, context: context)
                    .browserSidebarReorderSectionIndicator(
                        section,
                        state: sidebarInteraction.sidebarReorderState
                    )
            } else {
                BrowserSidebarListRows(list: list, context: context) { items in
                    // A cleared list has no row to draw the seam on, so it
                    // keeps a band under the new-tab row for the line to stand
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
