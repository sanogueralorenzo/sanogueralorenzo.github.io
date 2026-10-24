import SwiftUI

/// A committed web page, rendered the one way Crest renders web pages on this
/// platform.
///
/// Every mobile surface that shows live web content goes through here: the
/// selected tab in `MobileBrowserDetailView`, a tab the iPhone address bar's
/// swipe slides in beside it, and each iPad split column. They differ in the
/// `MobileBrowserPageViewport` they are handed and in whether a tap asks for
/// focus — never in the treatment of the page itself. A grouped tab and a plain
/// tab therefore render identically by construction rather than by two places
/// agreeing to.
///
/// The safe-area treatment belongs here rather than at each call site because
/// it is part of that treatment: a page told to obscure the system safe areas
/// must also be laid out through them, and separating the two is exactly how a
/// surface ends up drawing a page behind the status bar.
struct MobileBrowserLivePageView: View {
    let page: MobileBrowserPage
    let viewport: MobileBrowserPageViewport
    let isActive: Bool
    var handleInteraction: (() -> Void)?
    /// An unfocused card's request to become the focused one. `nil` wherever
    /// the page on screen is already the focused one.
    var requestFocus: (() -> Void)?
    /// Keeps the page out of VoiceOver's reach while it waits out of sight.
    var hidesFromAccessibility = false

    var body: some View {
        MobileBrowserWebView(
            page: page,
            viewport: viewport,
            handleInteraction: handleInteraction,
            requestFocus: requestFocus,
            hidesFromAccessibility: hidesFromAccessibility
        )
        // Keep the document color behind WebKit; docked bars own their native
        // background independently of the page's theme.
        .background(
            Color(
                uiColor: BrowserPageSurfacePresentation.revealsWebContent(
                    committedNavigationCount: page.committedNavigationCount
                )
                    ? page.themeColor
                        ?? page.underPageColor
                        ?? .systemBackground
                    : .clear
            )
        )
        .modifier(
            BrowserPageToolbarHost {
                if !viewport.obscuresSystemSafeAreas, isActive,
                    !page.readerModeState.isActive, page.translation.showsToolbar
                {
                    BrowserTranslationToolbar(translation: page.translation)
                }
            }
        )
        .modifier(
            BrowserTranslationHost(
                translation: page.translation, page: page,
                isActive: isActive, isLoading: page.live.isLoading,
                isReaderActive: page.readerModeState.isActive
            )
        )
        .id(page.tabID)
        .opacity(
            BrowserPageSurfacePresentation.revealsWebContent(
                committedNavigationCount: page.committedNavigationCount
            ) ? 1 : 0
        )
        // Every edge: the host reaches the side safe areas too, so the frame
        // insets are what keep the page clear of them, once, and the page's
        // color fills the side column behind the system's controls.
        .ignoresSafeArea(
            .container,
            edges: viewport.obscuresSystemSafeAreas ? .all : []
        )
        .safeAreaPadding(.bottom, viewport.obscuresSystemSafeAreas ? 0 : viewport.bottomChromeHeight)
    }
}
