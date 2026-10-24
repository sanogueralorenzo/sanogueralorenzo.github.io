import SwiftUI

struct MobileCompactBrowserSurface<
    DockedSidebar: View,
    FloatingSidebar: View,
    Page: View
>: View {
    @Environment(\.browserChromeAppearance) private var appearance
    @Environment(\.colorScheme) private var colorScheme

    let compactShowsPage: Bool
    @Binding var isPagePresented: Bool
    let usesDockedDetailPresentation: Bool
    let sidebarPresentation: BrowserSidebarPresentation
    @Binding var preferredSidebarWidth: CGFloat
    let space: SpaceModel?
    let spaces: [SpaceModel]
    @State private var floatingPagerPresentation = SpacePagerPresentation()
    let reduceTransparency: Bool
    let layoutDirection: LayoutDirection
    let usesBorderlessFloatingPageFrame: Bool
    let isStartPage: Bool
    let hasActivePage: Bool
    let completedNavigationCount: Int
    let hasSelectedSpace: Bool
    /// The page on show, which a swipe in from the frame around it steps.
    let selectedPage: MobileBrowserPage?
    let showSidebar: () -> Void
    let handlePageInteraction: () -> Void
    let commitSidebarWidth: (CGFloat) -> Void
    let dockedSidebar: DockedSidebar
    let floatingSidebar: FloatingSidebar
    let page: Page

    var body: some View {
        dockedSidebar
            .allowsHitTesting(!compactShowsPage)
            .accessibilityHidden(compactShowsPage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fullScreenCover(isPresented: $isPagePresented) {
                if usesDockedDetailPresentation {
                    // Preserve the original phone tab-to-detail composition.
                    // Its backdrop owns the safe-area tint and its detail owns
                    // the floating URL controls.
                    page
                        .environment(\.mobileBrowserSideToolbarIsHosted, false)
                } else {
                    ZStack {
                        SpaceBackdropBlend(spaces: spaces, selectedSpace: space) {
                            BrowserWindowAtmosphere(space: $0)
                        }
                        .ignoresSafeArea()

                        GeometryReader { proxy in
                            MobileRegularBrowserLayout(
                                layout: MobileRegularWindowLayout(
                                    availableWidth: proxy.size.width,
                                    preferredSidebarWidth: preferredSidebarWidth
                                ),
                                sidebarPresentation: sidebarPresentation,
                                preferredSidebarWidth: $preferredSidebarWidth,
                                reduceTransparency: reduceTransparency,
                                layoutDirection: layoutDirection,
                                space: space,
                                spaces: spaces,
                                showSidebar: showSidebar,
                                commitSidebarWidth: commitSidebarWidth,
                                sidebar: floatingSidebar,
                                detail: floatingDetail
                            )
                        }
                    }
                    .environment(\.spacePagerPresentation, floatingPagerPresentation)
                    .modifier(
                        MobileBrowserSideToolbarHost(
                            colorScheme: space?.settings.look.colorScheme(over: colorScheme)
                        )
                    )
                    .environment(\.mobileBrowserSideToolbarIsHosted, false)
                }
            }
    }

    private var floatingDetail: some View {
        BrowserRootDetailSurface(
            adjoinsLeadingSidebar: false,
            usesBorderlessFrame: usesBorderlessFloatingPageFrame,
            isStartPage: isStartPage,
            hasActivePage: hasActivePage,
            completedNavigationCount: completedNavigationCount,
            hasSelectedSpace: hasSelectedSpace,
            handleWebContentInteraction: handlePageInteraction,
            content: page
        )
        .overlay {
            if !usesBorderlessFloatingPageFrame {
                MobileHistorySwipeBorder(
                    insets: appearance.pageInsets(docked: false, direction: layoutDirection),
                    leadingPage: selectedPage,
                    trailingPage: selectedPage
                )
            }
        }
    }
}
