import SwiftUI

/// The landing band the current run keeps at its end.
///
/// A finger cannot aim at the seam between two rows that touch, so a shell that
/// draws its drop feedback on the rows themselves keeps a band of its own after
/// the last one. It is also the band a cleared list draws its insertion line
/// in: with no rows left it sits directly below the new-tab row, where the
/// first current tab would appear.
struct BrowserCurrentTabsEndDropTarget: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    /// The current section's top level, whose rows decide whether the band
    /// draws the line past the last of them.
    let list: SidebarListModel
    let context: BrowserSidebarListContext

    private var capabilities: BrowserInteractionCapabilities { context.capabilities }

    var body: some View {
        Color.clear
            .frame(height: bandHeight)
            .contentShape(.rect)
            .overlay(alignment: .top) {
                // The section's end draws the indicator only when no row is there to.
                if list.isEmpty {
                    BrowserTabDropIndicator(
                        location: dropLocation,
                        dragState: sidebarInteraction.tabDragState,
                        isTargeted: false
                    )
                }
            }
            .accessibilityHidden(true)
    }

    private var bandHeight: CGFloat {
        capabilities.tabListMetrics
            .sectionEndBandHeight
    }

    private var dropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: .current,
            folderID: nil,
            beforeTabID: nil
        )
    }
}
