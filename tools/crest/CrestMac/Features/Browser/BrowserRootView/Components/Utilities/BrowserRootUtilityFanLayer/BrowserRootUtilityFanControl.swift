import SwiftUI

/// The archive, history and downloads destinations, fanned out from the lists
/// button onto the page beside the sidebar.
struct BrowserRootUtilityFanControl: View {
    // MARK: - Variables

    let model: BrowserRootModel
    let proxy: GeometryProxy
    let localTriggerFrame: CGRect
    let sidebarOnRight: Bool

    @Environment(\.layoutDirection) private var layoutDirection

    /// Where the fan settles, from the left edge: beside the trigger, on the
    /// page's side of the sidebar.
    private var destinationX: CGFloat {
        let edgeOffset =
            BrowserUtilitySwitcherLayout.buttonSize / 2
            + BrowserUtilitySwitcherLayout.destinationGap
            + BrowserRootMetrics.utilityFanAdditionalEdgeOffset
        return sidebarOnRight
            ? localTriggerFrame.minX - edgeOffset
            : localTriggerFrame.maxX + edgeOffset
    }

    var body: some View {
        BrowserUtilityFanControl(
            isExpanded:
                model.sidebarPresentation.showsSidebar
                && model.chrome.utilityPresentation.isSwitcherExpanded,
            origin: CGPoint(
                x: positionX(localTriggerFrame.midX),
                y: localTriggerFrame.midY
            ),
            destination: CGPoint(
                x: positionX(destinationX),
                y: proxy.size.height / 2
            ),
            selectedSurface: model.chrome.utilityPresentation.surface,
            badgeColor: model.browser.shownSpace.flatMap {
                $0.settings.look.colors.first?.color
            }
                ?? .accentColor,
            downloads: model.selectedUtilityDownloads,
            newDownloadCount: model.newUtilityDownloads.count,
            select: model.chrome.presentUtility
        )
        .zIndex(BrowserRootMetrics.utilityFanZIndex)
    }

    // MARK: - Actions - Placement

    /// `x`, measured from the left edge, as `position` reads it: from the
    /// leading edge, which a right-to-left layout puts on the right.
    private func positionX(_ x: CGFloat) -> CGFloat {
        layoutDirection == .rightToLeft ? proxy.size.width - x : x
    }
}
