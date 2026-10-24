import SwiftUI

/// The landing band the unfiled saved run keeps at its end.
///
/// The tab half matches the current run's band: a shell that draws its drop
/// feedback on the rows needs somewhere to aim past the last one, and an empty
/// unfiled run needs a region at all. The folder half is what makes the band
/// the place a dragged folder lands beside the last root folder rather than
/// inside it.
struct BrowserSavedTabsEndDropTarget: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    /// The saved section's top level, whose unfiled rows decide whether the
    /// band draws the line past the last of them.
    let list: SidebarListModel
    let context: BrowserSidebarListContext

    private var capabilities: BrowserInteractionCapabilities { context.capabilities }

    var body: some View {
        Color.clear
            .frame(height: bandHeight)
            .contentShape(.rect)
            .overlay(alignment: .top) {
                // The section's end draws the indicator only when no row is there to.
                if !list.holdsTabRows {
                    BrowserTabDropIndicator(
                        location: tabLocation,
                        dragState: sidebarInteraction.tabDragState,
                        isTargeted: false
                    )
                }
            }
            .overlay(alignment: .bottom) {
                BrowserFolderDropIndicator(
                    location: folderLocation,
                    dragState: sidebarInteraction.folderDragState,
                    isTargeted: false
                )
            }
            .accessibilityHidden(true)
    }

    private var bandHeight: CGFloat {
        capabilities.tabListMetrics
            .savedSectionEndBandHeight
    }

    private var tabLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: .saved,
            folderID: nil,
            beforeTabID: nil
        )
    }

    private var folderLocation: BrowserFolderDropLocation {
        BrowserFolderDropLocation(parentID: nil, beforeSiblingID: nil)
    }
}
