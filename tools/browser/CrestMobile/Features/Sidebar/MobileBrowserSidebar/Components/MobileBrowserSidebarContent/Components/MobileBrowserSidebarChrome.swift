import SwiftUI

struct MobileBrowserSidebarChrome: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        VStack(spacing: 0) {
            MobileBrowserSidebarTopChrome(configuration: configuration)

            BrowserSpaceSwitcher(
                browser: configuration.context.browser,
                downloadCenter: configuration.context.pageAccess.downloadCenter,
                capabilities: configuration.context.capabilities,
                selectSpace: configuration.context.selectSpace
            )
        }
        .modifier(
            SpaceForegroundBlend(
                spaces: configuration.context.availableSpaces,
                selectedSpaceID: configuration.context.browser.shownSpace?.id))
    }
}
