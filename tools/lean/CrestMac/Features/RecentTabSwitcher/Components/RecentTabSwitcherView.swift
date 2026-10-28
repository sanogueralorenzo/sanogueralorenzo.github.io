import SwiftUI

/// The recent tabs: one card for each item, the highlighted one ringed.
struct RecentTabSwitcherView: View {
    let model: RecentTabSwitcherModel
    /// How far the cards shrink so the panel fits the display.
    let scale: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CrestRadius.panel, style: .continuous)
        HStack(spacing: RecentTabSwitcherMetrics.cardSpacing) {
            ForEach(Array(model.session.items.enumerated()), id: \.offset) { index, item in
                RecentTabSwitcherCard(
                    model: model, item: item, index: index, isHighlighted: index == model.session.highlightedIndex)
            }
        }
        .padding(RecentTabSwitcherMetrics.panelPadding)
        .scaleEffect(scale, anchor: .center)
        .frame(width: RecentTabSwitcherMetrics.panelSize(for: model.session.items, scale: scale).width)
        .frame(height: RecentTabSwitcherMetrics.panelSize(for: model.session.items, scale: scale).height)
        .modifier(BrowserCommandPaletteShellMaterial(shape: shape, reduceTransparency: reduceTransparency))
        .clipShape(shape)
        .animation(CrestMotion.surface.unlessReducingMotion(reduceMotion), value: model.session.highlightedIndex)
        .coordinateSpace(.named(RecentTabSwitcherMetrics.coordinateSpace))
        .onContinuousHover(coordinateSpace: .named(RecentTabSwitcherMetrics.coordinateSpace)) { phase in
            if case .active(let point) = phase { model.pointerMoved(to: point) }
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            model.panelFrame = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Recent tabs"))
    }
}

/// One item: its page, or both pages of a split side by side.
private struct RecentTabSwitcherCard: View {
    let model: RecentTabSwitcherModel
    let item: RecentTabItem
    let index: Int
    let isHighlighted: Bool

    var body: some View {
        let tabs = model.tabs(of: item)
        let pageWidth = RecentTabSwitcherMetrics.pageWidth(pageCount: item.tabIDs.count)
        Button {
            model.commit(index)
        } label: {
            HStack(alignment: .top, spacing: CrestSpacing.small) {
                ForEach(tabs) { tab in
                    RecentTabSwitcherPage(model: model, tab: tab, width: pageWidth)
                }
            }
            .padding(CrestSpacing.small)
            .crestInteractiveSurface(
                isSelected: isHighlighted, isHovering: false, cornerRadius: CrestRadius.card,
                selectedBorderColor: CrestColor.selectedBorder,
                selectedBorderWidth: RecentTabSwitcherMetrics.highlightRingWidth)
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(RecentTabSwitcherMetrics.coordinateSpace))
        } action: {
            model.cardFrames[index] = $0
        }
        .accessibilityLabel(Text(model.spokenTitle(at: index)))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

/// A page's picture over its favicon and title, or its favicon large on the
/// tab's colour while no picture exists.
private struct RecentTabSwitcherPage: View {
    let model: RecentTabSwitcherModel
    let tab: TabStateModel
    let width: CGFloat

    var body: some View {
        let favicon = BrowserTabFaviconSubject(tab: tab, image: model.browser.core.state.favicons.icon(of: tab.id))
        let profileID = model.browser.shownSpace?.profileID
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            thumbnail(favicon: favicon, profileID: profileID)
                .frame(width: width, height: RecentTabSwitcherMetrics.thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: CrestRadius.compact, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: CrestRadius.compact, style: .continuous)
                        .strokeBorder(CrestColor.subtleBorder, lineWidth: CrestLayout.hairline)
                }
            HStack(spacing: CrestSpacing.small) {
                TabFaviconView(subject: favicon, profileID: profileID, size: RecentTabSwitcherMetrics.smallFaviconSize)
                Text(tab.shownTitle)
                    .font(CrestTypography.metadata)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: width, alignment: .leading)
        }
    }

    @ViewBuilder
    private func thumbnail(favicon: BrowserTabFaviconSubject, profileID: UUID?) -> some View {
        if let image = model.snapshots.images[tab.id] {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: RecentTabSwitcherMetrics.thumbnailHeight, alignment: .topLeading)
        } else {
            ZStack {
                Rectangle().fill(tabColor)
                TabFaviconView(subject: favicon, profileID: profileID, size: RecentTabSwitcherMetrics.largeFaviconSize)
            }
        }
    }

    /// The tab's own colour, or the chrome's when it has none.
    private var tabColor: Color {
        guard let accent = tab.iconTint else { return CrestColor.chromeSurface }
        return Color(red: accent.red, green: accent.green, blue: accent.blue)
            .opacity(CrestOpacity.prominentStatusSurface)
    }
}

/// Sizes of the panel's parts.
enum RecentTabSwitcherMetrics {
    static let cardSpacing: CGFloat = CrestSpacing.small
    static let panelPadding: CGFloat = CrestSpacing.large
    static let thumbnailHeight: CGFloat = 112
    static let singlePageWidth: CGFloat = 176
    static let splitPageWidth: CGFloat = 136
    static let largeFaviconSize: CGFloat = 40
    static let smallFaviconSize: CGFloat = 16
    static let coordinateSpace = "recent-tab-switcher-panel"
    static let highlightRingWidth: CGFloat = 2
    /// The room the panel keeps from the window's edges before it shrinks.
    static let windowMargin: CGFloat = CrestSpacing.large
    private static let titleRowHeight: CGFloat = 24

    static func pageWidth(pageCount: Int) -> CGFloat {
        pageCount > 1 ? splitPageWidth : singlePageWidth
    }

    /// The panel at full size, before any shrinking.
    static func naturalSize(for items: [RecentTabItem]) -> CGSize {
        let cards = items.map { item -> CGFloat in
            let count = CGFloat(max(item.tabIDs.count, 1))
            return pageWidth(pageCount: item.tabIDs.count) * count + CrestSpacing.small * (count - 1)
                + CrestSpacing.small * 2
        }
        let width = cards.reduce(0, +) + cardSpacing * CGFloat(max(cards.count - 1, 0)) + panelPadding * 2
        let height = thumbnailHeight + titleRowHeight + CrestSpacing.small * 3 + panelPadding * 2
        return CGSize(width: width, height: height)
    }

    /// The panel once its cards shrink by `scale`.
    static func panelSize(for items: [RecentTabItem], scale: CGFloat) -> CGSize {
        let natural = naturalSize(for: items)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }
}
