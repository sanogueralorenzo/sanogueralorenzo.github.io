import SwiftUI

/// The disc a tab icon's corner badge sits on: the window's ground ringed by
/// a hairline, sized against the row's favicon. A favicon can be any colour,
/// so a mark reads only against this plain ground.
struct TabFaviconBadgeDisc: ViewModifier {
    // MARK: - Variables

    var diameter = TabFaviconBadge.diameter

    /// The mark inside the disc.
    var markSize = TabFaviconBadge.markSize

    /// The favicon's scale against a default-density row's.
    var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .frame(width: markSize * scale, height: markSize * scale)
            .frame(width: diameter * scale, height: diameter * scale)
            .background(.background, in: .circle)
            .overlay {
                Circle()
                    .strokeBorder(CrestColor.subtleBorder, lineWidth: CrestLayout.hairline)
            }
    }
}
