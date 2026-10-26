import SwiftUI

/// The window's Space and navigation controls stay fixed above the moving tabs.
struct SidebarChrome: View {
    let context: BrowserSidebarContext
    let pages: BrowserPagePool
    let activateAddress: () -> Void
    let openNewTab: () -> Void

    var body: some View {
        if let space = context.browser.shownSpace {
            BrowserSidebarSpaceControls(
                context: context, space: space, pages: pages,
                activateAddress: activateAddress, openNewTab: openNewTab
            )
            .background {
                BrowserWindowTitleBarSurface()
            }
            .modifier(BrowserChromeForeground())
        }
    }
}
