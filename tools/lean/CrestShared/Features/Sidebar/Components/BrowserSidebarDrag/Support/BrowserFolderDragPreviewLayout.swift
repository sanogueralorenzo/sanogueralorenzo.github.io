import CoreGraphics

enum BrowserFolderDragPreviewLayout {
    static let height = BrowserTabDragPreviewLayout.rowSize.height

    static func width(for sourceWidth: CGFloat) -> CGFloat {
        BrowserTabDragPreviewLayout.resolvedRowWidth(sourceWidth)
    }

    static func rowWidth(forSourceWidth sourceWidth: CGFloat) -> CGFloat {
        BrowserTabDragPreviewLayout.rowWidth(forSourceWidth: sourceWidth)
    }
}
