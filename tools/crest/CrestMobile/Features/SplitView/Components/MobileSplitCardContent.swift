import SwiftUI

/// One split card's interior on iPadOS: the per-member twin of what
/// `MobileBrowserDetailView` renders for the selected tab.
///
/// The iPad's columns use it for each column, differing from the selected tab
/// in the viewport they are handed and how focus is asked for, not in what a
/// card shows. A live page goes through the same `MobileBrowserLivePageView`
/// the selected tab does, with the same viewport, so a grouped tab renders
/// exactly like the plain tab it is. An iPhone shows one card at a time, as
/// the selected tab itself.
///
/// A card resolves its **own** member's page. That is not a stylistic
/// preference: `MobileBrowserWebHostView.attach(_:)` silently takes a web view
/// away from whatever superview already had it, so two cards sharing one page
/// would leave one blank and the other holding a view the first still believes
/// it owns.
///
/// Page-owned chrome — the find bar, the credential prompt — deliberately stays
/// with the focused card in `MobileBrowserDetailView`. A card renders content and
/// nothing else.
struct MobileSplitCardContent: View {
    let member: TabStateModel
    let space: SpaceModel
    let pages: MobileBrowserPageStore
    let viewport: MobileBrowserPageViewport
    let failureLayout: BrowserNavigationFailureLayout
    var handleInteraction: (() -> Void)?
    /// A tap's request to make this card the focused one. `nil` where focus is
    /// not a tap away, because the card on screen is already the focused one.
    var requestFocus: (() -> Void)?

    var body: some View {
        let page = residentPage
        switch PagePresentation.of(member.surface, page: page) {
        case .nativeContent:
            BrowserNativeTabHost(tab: member, space: space, bottomChromeHeight: viewport.bottomChromeHeight)
                .modifier(MobileSplitCardFocusTapModifier(requestFocus: requestFocus))
        case .livePage:
            if let page {
                liveSurface(page)
            } else {
                unloadedSurface
            }
        case .navigationFailure:
            if let page, let failure = page.live.failure {
                BrowserNavigationFailureView(
                    failure: failure,
                    branding: space.settings.look,
                    layout: failureLayout,
                    canGoBack: page.canReturnFromNavigationFailure,
                    canProceed: page.canProceedAfterCertificateFailure,
                    retry: page.retryAfterNavigationFailure,
                    goBack: page.returnFromNavigationFailure,
                    proceed: page.proceedAfterCertificateFailure
                )
                .modifier(MobileSplitCardFocusTapModifier(requestFocus: requestFocus))
            } else {
                unloadedSurface
            }
        default:
            // A Start Page has no committed navigation to render beside its
            // siblings, and an evicted neighbour is waiting to be shown again.
            // Both read as an empty card rather than as chrome that would
            // claim the space.
            unloadedSurface
        }
    }

    private func liveSurface(_ page: MobileBrowserPage) -> some View {
        MobileBrowserLivePageView(
            page: page,
            viewport: viewport,
            isActive: pages.activePage === page,
            handleInteraction: handleInteraction,
            requestFocus: requestFocus
        )
    }

    private var unloadedSurface: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
            .modifier(MobileSplitCardFocusTapModifier(requestFocus: requestFocus))
    }

    /// The card's page, or `nil` when this member has no live runtime right now —
    /// never yet prepared, or reclaimed under critical pressure.
    private var residentPage: MobileBrowserPage? {
        pages.residentPage(
            matching: BrowserTabRuntimeAssignment(
                tabID: member.id,
                spaceID: space.id,
                profileID: space.profileID
            )
        )
    }
}
