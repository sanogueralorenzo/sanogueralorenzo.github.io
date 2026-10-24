import SwiftUI

/// One Space in the switcher: its crest, and the region a lifted tab can be
/// dropped on to move it here.
///
/// Selecting is not the segment's job. Both arrangements hand their segments
/// to a control that already owns selection — a segmented picker's tag on one
/// side, the icon picker's button on the other — so the segment registers its
/// drop zone and otherwise stays out of the way.
struct BrowserSpacePickerSegment: View {
    let space: BrowserSpaceIdentity
    let reorderState: BrowserSidebarReorderState
    let metrics: BrowserSpacePickerMetrics

    var body: some View {
        BrowserSpacePickerIcon(space: space, metrics: metrics)
            .browserSidebarReorderZone(
                .space(space.assignment),
                state: reorderState
            )
            .accessibilityHint(
                "Select this Space, or drop a tab to move it here"
            )
    }
}
