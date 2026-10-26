import SwiftUI

struct MobileBrowserSidebarPager: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        GeometryReader { _ in
            VStack(spacing: 0) {
                MobileBrowserSidebarChrome(configuration: configuration)
                    .fixedSize(horizontal: false, vertical: true)
                BrowserSidebarSpacePager(context: configuration.context) { space, isSelected in
                    MobileBrowserSidebarSpaceSurface(configuration: configuration, space: space, isSelected: isSelected)
                }
            }
        }
        .background {
            if configuration.showsPageBackdrop {
                SpaceBackdropBlend(
                    spaces: configuration.context.availableSpaces,
                    selectedSpace: configuration.context.browser.shownSpace
                ) { space in
                    if let space {
                        BrowserSpaceBannerBackground(branding: space.settings.look)
                    } else {
                        Color(uiColor: .systemBackground)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
}
