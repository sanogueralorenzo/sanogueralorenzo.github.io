import SwiftUI

struct BrowserStartPageContent: View {
    /// The tab this start page belongs to.
    ///
    /// Split View renders one of these per card, so the surface can no longer
    /// assume it is speaking for the selected tab. Every action still routes
    /// through `BrowserStore.isPaletteSourceAvailable`, which answers "unavailable"
    /// for a card that is not the focused one — an unfocused start page reads
    /// but does not act until a click makes it the focused card.
    let tab: TabStateModel?
    let space: SpaceModel?
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let tabPromotionNamespace: Namespace.ID
    let focusRequest: Int
    let isCommandPalettePresented: Bool
    /// The window's commands, which the page's palette offers once what is
    /// typed matches one. They run exactly as they do from the overlay.
    let commands: BrowserCommandPaletteCommandRegistry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let space {
            BrowserStartPage(
                browser: browser,
                space: space,
                isPrivateBrowsing: browser.isPrivateBrowsing,
                selectedTabID: tab?.id,
                isSourceAvailable: isSourceAvailable,
                selectTab: selectStartPageTab,
                openURL: openStartPageURL,
                isCommandPaletteObscured: isCommandPalettePresented,
                layout: .macOSPage,
                focusRequest: space.id == browser.selectedSpaceID && tab != nil && tab?.id == browser.shownTab?.id
                    ? focusRequest
                    : nil,
                promotion: tab.map { tab in
                    BrowserStartPagePromotion(
                        namespace: tabPromotionNamespace,
                        id: BrowserTabPromotionID.value(for: tab.id)
                    )
                },
                commands: commands
            )
        } else {
            BrowserUnloadedPageSurface()
        }
    }

    private func openStartPageURL(
        _ source: BrowserTabRuntimeAssignment,
        _ url: URL
    ) -> Bool {
        return withAnimation(
            CrestMotion.contentNavigation.unlessReducingMotion(reduceMotion)
        ) {
            BrowserStartPageNavigationAction(
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess
            ).perform(source, url: url)
        }
    }

    private func selectStartPageTab(
        _ source: BrowserTabRuntimeAssignment,
        _ target: BrowserTabRuntimeAssignment
    ) -> Bool {
        guard
            let destination = browser.paletteTarget(target, from: source, accessController: spaceAccess)
        else { return false }
        browser.selectSpace(destination.space.id)
        browser.selectTab(destination.tab.id)
        pages.select()
        return true
    }

    private func isSourceAvailable(
        _ source: BrowserTabRuntimeAssignment
    ) -> Bool {
        browser.isPaletteSourceAvailable(source, accessController: spaceAccess)
    }
}
