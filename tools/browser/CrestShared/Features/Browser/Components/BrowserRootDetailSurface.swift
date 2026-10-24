import SwiftUI

/// The single-surface half of a content area's branch: one page inside the root
/// frame, wherever the branch did not open a row of cards.
///
/// It exists so the two shells cannot assemble that frame differently. Every
/// argument `BrowserRootContentSurface` takes is a decision — the corner radius,
/// the brand seam, the page insets, whether the interior shows the Space's
/// atmosphere through it — and all of them belong to the page surface rather
/// than to a platform. The tap that stands the utility fan down rides along
/// because it is a property of the surface, not of what is drawn in it.
///
/// A borderless frame is the compact shell's placement, where the page runs to
/// the device edges and there is no frame left to draw.
struct BrowserRootDetailSurface<Content: View>: View {
    @Environment(\.browserChromeAppearance) private var appearance
    @Environment(\.layoutDirection) private var layoutDirection
    let adjoinsLeadingSidebar: Bool
    let usesBorderlessFrame: Bool
    let isStartPage: Bool
    let hasActivePage: Bool
    let completedNavigationCount: Int
    let hasSelectedSpace: Bool
    let handleWebContentInteraction: () -> Void
    var frameInsets: EdgeInsets? = nil
    let content: Content

    var body: some View {
        BrowserRootContentSurface(
            cornerRadius: usesBorderlessFrame
                ? 0
                : appearance.framedPageCornerRadius,
            seamWidth: usesBorderlessFrame
                ? 0
                : appearance.seamWidth,
            frameInsets: usesBorderlessFrame
                ? EdgeInsets()
                : frameInsets
                    ?? appearance.pageInsets(
                        docked: adjoinsLeadingSidebar, direction: layoutDirection
                    ),
            usesTransparentInnerSurface:
                BrowserPageSurfacePresentation.usesTransparentInnerSurface(
                    isStartPage: isStartPage,
                    hasActivePage: hasActivePage,
                    completedNavigationCount: completedNavigationCount
                ),
            showsFallbackBorder: !hasSelectedSpace,
            showsBoundary: !usesBorderlessFrame
        ) {
            content
        }
        .modifier(BrowserPlatformObservedTapModifier { handleWebContentInteraction() })
    }
}
