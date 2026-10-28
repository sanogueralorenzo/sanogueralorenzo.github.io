import SwiftUI

enum BrowserChromeLayout {
    static let sidebarTitlebarHeight: CGFloat = 36
    static let sidebarNavigationControlHitTarget: CGFloat = 40
    static let sidebarNavigationSymbolPointSize: CGFloat = 15
    static let addressEditingRingWidth: CGFloat = 0.5
    static let addressHeight = CGFloat(BrowserSidebarDensity(1).pinHeight(touch: false))
    static let addressCornerRadius = CrestRadius.compact
    static let sidebarMinimumWidth: CGFloat = 280
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
}
