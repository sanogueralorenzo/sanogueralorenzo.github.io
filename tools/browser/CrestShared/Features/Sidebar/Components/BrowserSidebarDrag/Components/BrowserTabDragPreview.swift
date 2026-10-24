import SwiftUI

struct BrowserTabDragPreview: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    /// The shape the preview is `progress` of the way toward. It always starts
    /// from the row, because the row is the shape the drag machinery measures a
    /// grab offset in.
    var targetShape = BrowserTabDragPreviewShape.pinnedTile
    let progress: CGFloat
    var rowWidth = BrowserTabDragPreviewLayout.rowSize.width
    var pinnedSize = BrowserTabDragPreviewLayout.pinnedSize
    var isSelected = false
    var isLoaded = true
    var rowMetrics = BrowserSidebarTabRowMetrics.pointer

    var body: some View {
        let metrics = BrowserTabDragPreviewLayout.metrics(
            from: .row,
            to: targetShape,
            progress: progress,
            rowWidth: rowWidth,
            pinnedSize: pinnedSize
        )
        let shape = RoundedRectangle(
            cornerRadius: BrowserTabDragPreviewLayout.cornerRadius(
                from: .row, to: targetShape, progress: progress,
                layerCornerRadius: BrowserSidebarMetrics.layerCornerRadius()),
            style: .continuous
        )
        // The row layout and the card's own centred layout cross-fade rather
        // than interpolate: a leading favicon beside a title and a stacked,
        // centred pair are different arrangements, not two ends of one.
        let rowOpacity = 1 - Double(metrics.cardContentWeight)

        ZStack(alignment: .leading) {
            CrestSurfaceLayer(shape: shape)
                .overlay {
                    shape.strokeBorder(CrestColor.subtleBorder, lineWidth: 0.5)
                }

            Button {
            } label: {
                BrowserSidebarTabLabel(
                    tab: tab, favicons: favicons, profileID: profileID, isSelected: isSelected,
                    isLoaded: isLoaded, metrics: rowMetrics,
                    leadingInset: BrowserSidebarMetrics.layerInset + rowMetrics.contentLeadingInset,
                    titleOpacity: metrics.titleOpacity,
                    iconOffset: ((metrics.width / 2) - rowIconCenter) * metrics.contentCentering)
            }
            .buttonStyle(.plain)
            .frame(width: metrics.width, height: metrics.height)
            .opacity(rowOpacity)
            .allowsHitTesting(false)

            if metrics.cardContentWeight > 0 {
                cardContent
                    .opacity(Double(metrics.cardContentWeight))
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        .shadow(
            color: .black.opacity(0.22),
            radius: 10,
            y: 5
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.shownTitle)
    }

    private var rowIconCenter: CGFloat {
        BrowserSidebarMetrics.layerInset + rowMetrics.contentLeadingInset + (rowMetrics.faviconSlot?.width ?? 18) / 2
    }

    /// The page-shaped drop preview: what the tab looks like once it is a card.
    /// A favicon and a title stand in for the page — a live snapshot would have
    /// to be captured from a web view mid-drag, which this release does not do.
    private var cardContent: some View {
        VStack(spacing: CrestSpacing.small) {
            TabStateFaviconView(tab: tab, favicons: favicons, profileID: profileID, size: 32)
            Text(tab.shownTitle)
                .font(CrestTypography.controlTitle)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, CrestSpacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
