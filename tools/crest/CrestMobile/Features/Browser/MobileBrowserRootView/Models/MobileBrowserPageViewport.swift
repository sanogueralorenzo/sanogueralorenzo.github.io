import SwiftUI
import UIKit

/// Everything a mobile surface has to know to render one live web page at the
/// right size: whether it draws through the system safe areas, what those areas
/// measure, and how much floating chrome covers its bottom.
///
/// The three travel together because they are only ever right together. A tab
/// presented on its own and the same tab presented as a split card resolve one
/// value in `MobileBrowserDetailView` and hand it to one page view, so a card
/// cannot drift into a different viewport treatment than the plain tab it is.
///
/// `systemSafeAreaInsets` is carried as data rather than read from the hosting
/// view for the same reason. Every page the content area draws — the shown
/// tab, an iPad split column, a tab the iPhone address bar's swipe slides in —
/// is handed the one measurement `MobileBrowserDetailView` takes, so none of
/// them can lay its web content out on a different row from the others.
struct MobileBrowserPageViewport: Equatable {
    // MARK: - Static Variables

    /// The 44-point controls plus six points above and below their glass scope.
    static let compactToolbarHeight: CGFloat = 56
    static let compactDomainChipHeight = MobileCompactDomainChipLayout.minimumHitTarget

    /// A page that stays inside the bounds its container gives it: the iPad's
    /// rounded detail surface and every iPad split column, where the window
    /// chrome — not the page — owns the safe areas.
    static let inline = MobileBrowserPageViewport(
        obscuresSystemSafeAreas: false,
        systemSafeAreaInsets: .zero,
        bottomChromeHeight: 0
    )

    // MARK: - Variables

    /// Whether the page draws through the system safe areas and absorbs them
    /// itself, which is how every compact full-bleed surface presents a page.
    let obscuresSystemSafeAreas: Bool
    /// The window's safe areas as SwiftUI reports them for the page area,
    /// including any chrome inset above the page.
    let systemSafeAreaInsets: UIEdgeInsets
    /// The floating chrome that covers the bottom of the page, reported to
    /// WebKit as obscured rather than subtracted from the web view's frame.
    let bottomChromeHeight: CGFloat

    /// How far the web view's frame stands in from its host: clear of the
    /// side and top safe areas, and full height so content scrolls on under
    /// the bottom chrome.
    var webViewFrameInsets: UIEdgeInsets {
        guard obscuresSystemSafeAreas else { return .zero }
        return UIEdgeInsets(
            top: systemSafeAreaInsets.top,
            left: systemSafeAreaInsets.left,
            bottom: 0,
            right: systemSafeAreaInsets.right
        )
    }

    /// What the bottom safe area and chrome cover of the page.
    var chromeOverlayInsets: UIEdgeInsets {
        guard obscuresSystemSafeAreas else { return .zero }
        return Self.chromeOverlayInsets(
            safeAreaInsets: systemSafeAreaInsets,
            bottomChromeHeight: bottomChromeHeight
        )
    }

    /// The range WebKit's viewport moves through as the compact toolbar
    /// collapses to the domain chip and back.
    var viewportRangeInsets: (minimum: UIEdgeInsets, maximum: UIEdgeInsets) {
        guard obscuresSystemSafeAreas else {
            return (minimum: UIEdgeInsets.zero, maximum: UIEdgeInsets.zero)
        }
        return (
            minimum: Self.chromeOverlayInsets(
                safeAreaInsets: systemSafeAreaInsets,
                bottomChromeHeight: Self.compactDomainChipHeight
            ),
            maximum: Self.chromeOverlayInsets(
                safeAreaInsets: systemSafeAreaInsets,
                bottomChromeHeight: Self.compactToolbarHeight
            )
        )
    }

    // MARK: - Actions - Insets

    /// SwiftUI's directional safe area as the physical one UIKit lays out with.
    static func systemSafeAreaInsets(
        _ insets: EdgeInsets,
        layoutDirection: LayoutDirection
    ) -> UIEdgeInsets {
        let isRightToLeft = layoutDirection == .rightToLeft
        return UIEdgeInsets(
            top: insets.top,
            left: isRightToLeft ? insets.trailing : insets.leading,
            bottom: insets.bottom,
            right: isRightToLeft ? insets.leading : insets.trailing
        )
    }

    private static func chromeOverlayInsets(
        safeAreaInsets: UIEdgeInsets,
        bottomChromeHeight: CGFloat
    ) -> UIEdgeInsets {
        UIEdgeInsets(
            top: 0,
            left: 0,
            bottom: safeAreaInsets.bottom + max(0, bottomChromeHeight),
            right: 0
        )
    }
}
