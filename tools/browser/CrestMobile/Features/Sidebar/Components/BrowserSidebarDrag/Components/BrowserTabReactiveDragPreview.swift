import SwiftUI

struct BrowserTabReactiveDragPreview: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let dragState: BrowserTabDragState
    var reduceMotionOverride: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        BrowserTabDragPreview(
            tab: tab,
            favicons: favicons,
            profileID: profileID,
            progress: BrowserTabDragPreviewLayout.progress(
                for: dragState.currentPlacement ?? tab.placement
            ),
            rowMetrics: .touch
        )
        .animation(
            CrestMotion.dragPreview.unlessReducingMotion(reduceMotionOverride ?? reduceMotion),
            value: dragState.currentPlacement
        )
    }
}
