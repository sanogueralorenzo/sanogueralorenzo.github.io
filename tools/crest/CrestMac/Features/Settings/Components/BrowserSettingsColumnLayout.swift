import SwiftUI

/// Places a settings page's one column of rows: centred in the page, at least
/// the minimum margin from each edge, and running past the trailing edge,
/// never over the Settings sidebar, when its rows need more than the page.
///
/// A layout rather than a `GeometryReader`, so a page that changes size, as
/// it does under a drag of the window border, moves the column without
/// rebuilding a row in it.
struct BrowserSettingsColumnLayout: Layout {
    let columnWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let inset = BrowserSettingsLayout.formInset(for: bounds.width, columnWidth: columnWidth)
        for subview in subviews {
            subview.place(
                at: CGPoint(x: bounds.minX + inset, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: max(0, bounds.width - 2 * inset), height: bounds.height))
        }
    }
}
