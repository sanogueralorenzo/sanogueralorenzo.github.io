import SwiftUI

struct BrowserTabAppearanceSurface: ViewModifier {
    let isPinned: Bool
    let isSelected: Bool
    let isHovering: Bool
    var selectionEmphasis = false
    @Environment(\.sidebarLayerDepth) private var depth
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.modifier(
            CrestInteractiveSurfaceModifier(
                isSelected: isSelected, selectionEmphasis: selectionEmphasis,
                isHovering: isHovering, cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: depth),
                isPressed: false, showsRestingSurface: isPinned,
                selectedBorderColor: isPinned && contrast != .increased ? .clear : CrestColor.selectedBorder,
                selectedBorderWidth: isPinned ? CrestLayout.pinnedAccentBorderWidth : 1,
                customSelectedFill: isPinned ? CrestColor.selection : nil,
                customRestingFill: isPinned ? CrestColor.chromeSurface : nil,
                restingBorderColor: isPinned && contrast == .increased ? CrestColor.subtleBorder : .clear))
    }
}
