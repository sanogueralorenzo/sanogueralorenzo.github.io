import SwiftUI

struct BrowserDetailContent: View {
    let page: BrowserPage?
    /// The tab this content is rendering. The single-page path passes the
    /// selected tab; a Split View card passes its own member, which is what
    /// keeps an unfocused start-page card bound to itself.
    let tab: TabStateModel?
    let space: SpaceModel?
    let pagePresentation: PagePresentation
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let tabPromotionNamespace: Namespace.ID
    let startPageFocusRequest: Int
    let isCommandPalettePresented: Bool
    /// The window's commands, for the Start Page's palette.
    let commands: BrowserCommandPaletteCommandRegistry

    var body: some View {
        if let tab, let space, !spaceAccess.isLocked(space), pages.isMirroringPage(for: tab.id) {
            BrowserMirroredPageContent(tabID: tab.id, pages: pages)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch pagePresentation {
        case .nativeContent:
            if let tab, let space {
                BrowserNativeTabHost(tab: tab, space: space)
                    .environment(\.browserNativeTabs, pages.nativeTabs)
                    .environment(
                        \.browserNativeTabActions,
                        BrowserNativeTabActions(
                            browser: browser, spaceAccess: spaceAccess,
                            didOpenURL: { pages.select() }))
            }
        case .startPage:
            BrowserStartPageContent(
                tab: tab,
                space: space,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                tabPromotionNamespace: tabPromotionNamespace,
                focusRequest: startPageFocusRequest,
                isCommandPalettePresented: isCommandPalettePresented,
                commands: commands
            )
        case .livePage, .navigationFailure, .processFailure:
            BrowserLivePageContent(
                page: page,
                browser: browser,
                pages: pages
            )
        case .unloaded, .automaticRestore:
            BrowserUnloadedPageSurface()
        default:
            Color.clear
        }
    }
}
