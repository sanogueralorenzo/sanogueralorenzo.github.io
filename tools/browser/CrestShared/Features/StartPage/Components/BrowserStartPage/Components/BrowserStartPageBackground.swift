import SwiftUI

/// What shows behind the start page's stack.
///
/// A shell that puts the page on the Space's banner says so in its layout; the
/// rest leave the page clear and let whatever the shell already drew show
/// through.
struct BrowserStartPageBackground: View {
    let page: BrowserStartPage

    @ViewBuilder
    var body: some View {
        if page.layout.backgroundIgnoresSafeArea {
            backdrop
                .ignoresSafeArea()
                .accessibilityHidden(true)
        } else {
            backdrop
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if page.layout.showsSpaceBanner, let space = page.space {
            BrowserSpaceBannerBackground(branding: space.settings.look.shown)
        } else {
            Color.clear
        }
    }
}
