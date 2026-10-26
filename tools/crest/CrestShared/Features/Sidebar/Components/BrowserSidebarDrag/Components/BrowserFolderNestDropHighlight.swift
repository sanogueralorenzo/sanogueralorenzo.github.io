import SwiftUI

/// The outline a row wears while releasing would file the lifted item inside
/// it: an open tab a lifted tab would make a folder with, or a collapsed
/// folder a lifted folder would move into.
///
/// Whether that is what release means is resolved by
/// `BrowserSidebarReorderState` from the measured geometry, so this view reads
/// the answer rather than re-deriving it from a drag session. It reads it
/// itself, so only the outline redraws as a lift's target moves, never the
/// row it decorates.
struct BrowserFolderNestDropHighlight: View {
    /// What the outline marks.
    enum Target: Equatable {
        case currentTab(UUID)
        case folder(UUID)

        /// Whether releasing the lift `state` holds would file it inside the
        /// row this marks.
        @MainActor
        func isTargeted(in state: BrowserSidebarReorderState) -> Bool {
            switch self {
            case .currentTab(let tabID):
                state.resolvedTarget?.kind == .createCurrentFolder(tabID)
            case .folder(let folderID):
                state.isTargetedFolder(folderID)
                    && (state.lift?.item.showsFolderNestOutline ?? false)
            }
        }
    }

    let state: BrowserSidebarReorderState
    let target: Target
    /// How many folders hold the row this marks, whose bounds start at the
    /// sidebar's leading edge however deep the row is; the outline steps in
    /// and tightens to match the surface drawn there.
    var depth = 0

    var body: some View {
        if target.isTargeted(in: state) {
            let shape = RoundedRectangle(
                cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: depth), style: .continuous)
            shape
                .fill(CrestColor.dropIndicator.opacity(0.14))
                .overlay { shape.strokeBorder(CrestColor.dropIndicator, lineWidth: 1.5) }
                .padding(.leading, BrowserFolderLayout.surfaceLeadingInset(depth: depth))
                .padding(.trailing, BrowserSidebarMetrics.layerInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
