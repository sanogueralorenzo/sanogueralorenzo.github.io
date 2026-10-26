import SwiftUI

/// One hover boundary for a folder's header and all of its visible contents.
/// The header keeps a regular tab's height without extra vertical container padding.
struct BrowserFolderSectionSurface: ViewModifier {
    /// How many folders hold this one.
    var depth = 0
    var isSelected = false
    let folderID: UUID
    let reorder: BrowserSidebarReorderState
    private var isTargeted: Bool { reorder.isTargetedFolder(folderID) }

    @Environment(\.folderPreviewShowsHighlight) private var previewShowsHighlight
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .modifier(
                BrowserFolderHighlightSurface(
                    showsFill: previewShowsHighlight || isHovered || isSelected || isTargeted,
                    depth: depth,
                    isSelected: isSelected)
            )
            .onHover { isHovered = $0 }
            .animation(
                CrestMotion.surface.unlessReducingMotion(reduceMotion),
                value: isHovered || isTargeted || isSelected
            )
    }
}
