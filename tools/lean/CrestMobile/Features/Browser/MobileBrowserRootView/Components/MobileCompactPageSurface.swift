import SwiftUI

struct MobileCompactPageSurface<Backdrop: View, Detail: View>: View {
    // MARK: - Static Variables

    /// Whether a downward swipe may dismiss the full-screen page.
    private static var allowsInteractiveDismissal: Bool { false }

    // MARK: - Variables

    let selectedTab: TabStateModel?
    let isURLCopiedFeedbackVisible: Bool
    let pageFeedback: MobilePageFeedback?
    let reduceMotion: Bool
    let tabPromotionNamespace: Namespace.ID
    let completePagePresentation: () -> Void
    let backdrop: Backdrop
    let detail: Detail

    @ViewBuilder
    var body: some View {
        let page = ZStack {
            backdrop
            detail
        }
        .interactiveDismissDisabled(
            !Self.allowsInteractiveDismissal
        )
        .onAppear(perform: completePagePresentation)
        .overlay(alignment: .top) {
            MobileURLCopyFeedback(
                isVisible: isURLCopiedFeedbackVisible,
                topPadding: MobileBrowserRootLayout.compactOverlayTopPadding
            )
            if let pageFeedback {
                MobilePageFeedbackCapsule(
                    feedback: pageFeedback,
                    topPadding: MobileBrowserRootLayout.compactOverlayTopPadding
                )
            }
        }
        // The page covers the window, so it carries its own side toolbar; the
        // zoom below stays on the presentation's outermost view.
        .modifier(MobileBrowserSideToolbarHost())

        if reduceMotion {
            page
        } else if let selectedTab,
            selectedTab.isPromotionSource(isSelected: true)
        {
            page.navigationTransition(
                .zoom(
                    sourceID: BrowserTabPromotionID.value(for: selectedTab.id),
                    in: tabPromotionNamespace
                )
            )
        } else {
            page
        }
    }
}
