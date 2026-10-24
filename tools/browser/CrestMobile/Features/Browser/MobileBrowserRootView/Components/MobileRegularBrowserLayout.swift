import SwiftUI

/// The regular-width mobile shell uses the same sidebar surface and reservation
/// components as macOS. Mobile owns only the touch reveal control and the
/// narrow-window decision that a docked sidebar cannot consume an unusable page.
struct MobileRegularBrowserLayout<Sidebar: View, Detail: View>: View,
    BrowserChromeAnimating
{
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.browserChromeAppearance) private var appearance
    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement

    private var sidebarEdge: HorizontalEdge { appearance.sidebarEdge(in: layoutDirection) }

    let layout: MobileRegularWindowLayout
    let sidebarPresentation: BrowserSidebarPresentation
    @Binding var preferredSidebarWidth: CGFloat
    let reduceTransparency: Bool
    let layoutDirection: LayoutDirection
    let space: SpaceModel?
    var spaces: [SpaceModel] = []
    let showSidebar: () -> Void
    let commitSidebarWidth: (CGFloat) -> Void
    let sidebar: Sidebar
    let detail: Detail

    var body: some View {
        BrowserSidebarPageLayout(
            presentation: effectivePresentation, width: layout.reservedSidebarWidth, edge: sidebarEdge
        ) {
            detail
                // Extend only the page; sidebar controls keep their safe-area placement.
                .ignoresSafeArea(
                    .container,
                    edges: appearance.borderless || controlPlacement.movesControlsToToolbar ? .bottom : []
                )
        } sidebar: {
            BrowserRootSidebarSurfaceLayer(
                presentation: effectivePresentation,
                width: layout.sidebarWidth,
                edge: sidebarEdge,
                space: space,
                reduceTransparency: reduceTransparency,
                spaces: spaces,
                hoverChanged: { _ in }
            ) {
                sidebar
            }
            // Where the status bar keeps to the far end of a band across the
            // top, the sidebar takes the rest of the band.
            .safeAreaPadding(.top, sidebarTopMargin)
            .ignoresSafeArea(.container, edges: layout.runsSidebarToTopEdge ? .top : [])

        } controls: {
            if effectivePresentation == .collapsed {
                BrowserCollapsedSidebarRevealControl(
                    capabilities: BrowserInteractionCapabilities(
                        supportsTouch: true
                    ),
                    showSidebar: showSidebar, edge: sidebarEdge
                )
                .zIndex(BrowserRootMetrics.floatingSidebarZIndex)
            } else if effectivePresentation == .docked, !layout.followsFold {
                // Across a fold the fold sets the width, so there is nothing
                // to drag.
                BrowserSidebarResizeHandle(
                    width: $preferredSidebarWidth,
                    onResizeEnded: commitSidebarWidth, edge: sidebarEdge
                )
                .offset(
                    x: layoutDirection.leadingOffset(
                        (layout.sidebarWidth - MobileBrowserRootLayout.resizeHandleOverlap)
                            * (sidebarEdge == .leading ? 1 : -1))
                )
                .zIndex(BrowserRootMetrics.sidebarResizeControlZIndex)
            }
        }
        .animation(chromeAnimation(CrestMotion.collection), value: appearance.sidebarOnRight)
        .animation(
            chromeAnimation(
                effectivePresentation == .docked
                    ? CrestMotion.sidebarDockAttachment
                    : CrestMotion.sidebarMorph
            ),
            value: effectivePresentation
        )
    }

    /// How far the sidebar stands from the display's top edge where nothing
    /// above holds it off. With its controls in the side toolbar its address
    /// field leads, out in the rounded corner, so it clears the corner;
    /// beside the status bar its controls lead, clear of the corner, and keep
    /// the layout margin.
    private var sidebarTopMargin: CGFloat {
        if controlPlacement.movesControlsToToolbar {
            return MobileBrowserRootLayout.displayCornerClearance
        }
        return layout.runsSidebarToTopEdge ? MobileBrowserRootLayout.displayEdgeMargin : 0
    }

    /// Compact regular windows retain the desktop floating-card treatment, but
    /// do not reserve a sidebar width that would make the page unusable.
    private var effectivePresentation: BrowserSidebarPresentation {
        guard !layout.reservesSidebarWidth,
            sidebarPresentation != .collapsed
        else { return sidebarPresentation }
        return .floating
    }
}
