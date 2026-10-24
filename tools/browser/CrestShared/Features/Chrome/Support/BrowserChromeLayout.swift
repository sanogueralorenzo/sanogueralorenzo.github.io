import SwiftUI

enum BrowserChromeLayout {
    static let sidebarTitlebarHeight: CGFloat = 48
    static let sidebarNavigationControlHitTarget: CGFloat = 30
    static let sidebarNavigationSymbolPointSize: CGFloat = 15
    static let sidebarNavigationTrailingInset = CrestSpacing.medium
    static let addressEditingRingWidth: CGFloat = 0.5
    static let addressHeight: CGFloat = 36
    static let addressCornerRadius = CrestRadius.compact
    static let sidebarMinimumWidth: CGFloat = 200
    static let sidebarIdealWidth: CGFloat = 289
    static let sidebarMaximumWidth: CGFloat = 380
    static let pageFrameInset = CrestSpacing.small
    /// A page's corner where there is no window corner to follow: full screen,
    /// iPhone and iPad.
    static let pageCornerRadius: CGFloat = 13
    static let pageBrandSeamWidth: CGFloat = 1.5

    static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, sidebarMinimumWidth), sidebarMaximumWidth)
    }

    static func pageFrameInsets(
        adjoinsLeadingSidebar: Bool
    ) -> EdgeInsets {
        EdgeInsets(
            top: pageFrameInset,
            leading: adjoinsLeadingSidebar ? 0 : pageFrameInset,
            bottom: pageFrameInset,
            trailing: pageFrameInset
        )
    }
}
