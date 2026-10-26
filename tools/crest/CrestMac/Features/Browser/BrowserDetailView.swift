import SwiftUI

struct BrowserDetailView: View {
    let presentation: BrowserPageSurfacePresentation
    let browser: BrowserStore
    let pages: BrowserPagePool
    let tabPromotionNamespace: Namespace.ID
    let startPageFocusRequest: Int
    let isCommandPalettePresented: Bool
    /// The window's commands, for the Start Page's palette.
    let commands: BrowserCommandPaletteCommandRegistry
    var previewsStartPage = false

    var body: some View {
        let tab = presentation.singleTab
        let space = presentation.presentingSpace
        let page = tab.flatMap { tab in
            space.flatMap { pages.surfacePage(for: tab.id, in: $0) }
        }
        BrowserDetailContent(
            page: page,
            tab: tab,
            space: space,
            pagePresentation: previewsStartPage ? .startPage : .of(tab?.surface, page: page),
            browser: browser,
            pages: pages,
            tabPromotionNamespace: tabPromotionNamespace,
            startPageFocusRequest: startPageFocusRequest,
            isCommandPalettePresented: isCommandPalettePresented,
            commands: commands
        )
    }
}
