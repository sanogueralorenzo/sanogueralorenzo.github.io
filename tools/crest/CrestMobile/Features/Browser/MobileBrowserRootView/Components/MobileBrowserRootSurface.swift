import SwiftUI

struct MobileBrowserRootSurface<Compact: View, Regular: View, Palette: View>:
    View, BrowserChromeAnimating
{
    let presentation: MobileBrowserPresentation
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let navigation: MobileBrowserNavigationState
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceAccess: BrowserSpaceAccessController
    let preferredSidebarWidth: CGFloat
    let isCommandPalettePresented: Bool
    let isURLCopiedFeedbackVisible: Bool
    let pageFeedback: MobilePageFeedback?
    let reduceMotion: Bool
    let didPromoteTransientPage: () -> Void
    let compact: Compact
    let regular: (MobileRegularWindowLayout) -> Regular
    let palette: (EdgeInsets) -> Palette
    @Environment(\.layoutDirection) private var layoutDirection

    private var sidebarOnRight: Bool { BrowserDeviceAppearanceStore.shared.sidebarOnRight }

    var body: some View {
        ZStack {
            if !presentation.presentsPageOverTabViewer {
                SpaceBackdropBlend(
                    spaces: browser.availableSpaces,
                    selectedSpace: browser.shownSpace
                ) {
                    BrowserWindowAtmosphere(space: $0)
                }
                .ignoresSafeArea()
            }

            if presentation.presentsPageOverTabViewer {
                compact
            } else {
                GeometryReader { proxy in
                    let fold = MobileBrowserFold.dividing(proxy)
                    let layout = MobileRegularWindowLayout(
                        availableWidth: proxy.size.width,
                        preferredSidebarWidth: preferredSidebarWidth,
                        foldSpan: fold?.span(across: proxy.frame(in: .global), direction: layoutDirection),
                        sidebarEdge: BrowserChromeAppearance.sidebarEdge(
                            onRight: sidebarOnRight, in: layoutDirection),
                        presentsColumns: browser.shownCards.count > 1,
                        sharesTopBandWithStatusBar: MobileBrowserFold.isFoldable(proxy)
                            && proxy.size.height > proxy.size.width
                    )
                    regular(layout)
                        .environment(\.mobileBrowserFold, fold)
                        .allowsHitTesting(!isCommandPalettePresented)
                        .accessibilityHidden(isCommandPalettePresented)
                        .overlayPreferenceValue(BrowserRootPageBoundsKey.self) { anchor in
                            GeometryReader { pageProxy in
                                let rect = anchor.map { pageProxy[$0] } ?? CGRect(origin: .zero, size: pageProxy.size)
                                palette(
                                    BrowserChromeAppearance.contentInsets(
                                        for: rect, in: pageProxy.size, direction: layoutDirection))
                            }
                        }
                }
            }
        }
        .overlay {
            if presentation.presentsPageOverTabViewer && !navigation.compactShowsPage {
                MobileTransientBrowsingOverlay(
                    browser: browser,
                    pages: pages,
                    coordinator: transientBrowsing,
                    spaceAccess: spaceAccess,
                    didPromote: didPromoteTransientPage,
                    showsPeeks: false
                )
            }
        }
        .overlay(alignment: .top) {
            if !presentation.presentsPageOverTabViewer || !navigation.compactShowsPage {
                MobileURLCopyFeedback(
                    isVisible: isURLCopiedFeedbackVisible,
                    topPadding: presentation.overlayTopPadding
                )
                if let pageFeedback {
                    MobilePageFeedbackCapsule(
                        feedback: pageFeedback,
                        topPadding: presentation.overlayTopPadding
                    )
                }
            }
        }
        .onChange(of: transientBrowsing.orphanedPeeks(in: browser), initial: true) {
            transientBrowsing.reconcilePeeks(in: browser)
        }
        .onChange(of: transientBrowsing.peekRequests, initial: true) {
            pages.retainPeekPages(for: transientBrowsing.peekRequests)
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
        .animation(
            BrowserCommandSurfaceMorph.commandPaletteAnimation(reduceMotion: reduceMotion),
            value: isCommandPalettePresented
        )
    }
}
