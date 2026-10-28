import SwiftUI

/// One card of a macOS split: the per-card twin of `BrowserDetailView`.
///
/// Both resolve a page and a presentation and then hand the same
/// `BrowserDetailContent` the result, which is deliberate — the find bar, the
/// navigation-failure overlay, the credential chrome, and the developer toolbar
/// all live on `BrowserPage`, so a card that renders the same content view gets
/// every one of them for its own page with nothing per-card to maintain.
///
/// The difference is which tab it speaks for. `BrowserDetailView` speaks for the
/// selected tab; a card speaks for its own member, focused or not, and resolves
/// its page through the assignment-checked accessor so a Space switch mid-frame
/// can never bind a page belonging to another Space or profile.
///
/// The card registers its bounds for click selection and sidebar drag targets.
///
/// Every card's page, focused or not, reports its navigations to the core,
/// which keeps its tab row and history current.
struct BrowserSplitCardView: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let tab: TabStateModel
    let space: SpaceModel
    let browser: BrowserStore
    let pages: BrowserPagePool
    let tabPromotionNamespace: Namespace.ID
    let startPageFocusRequest: Int
    let isCommandPalettePresented: Bool
    /// The window's commands, for a Start Page card's palette.
    let commands: BrowserCommandPaletteCommandRegistry
    /// Where this card records its bounds for the surface's click monitor.
    let cardFrames: BrowserSplitCardFrameRegistry

    private var isSelectedSpace: Bool {
        browser.selectedSpaceID == space.id
    }

    var body: some View {
        let page = presentedPage
        BrowserDetailContent(
            page: page,
            tab: tab,
            space: space,
            pagePresentation: .of(tab.surface, page: page),
            browser: browser,
            pages: pages,
            tabPromotionNamespace: tabPromotionNamespace,
            startPageFocusRequest: startPageFocusRequest,
            isCommandPalettePresented: isCommandPalettePresented,
            commands: commands
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: BrowserSplitCardFrameRegistry.coordinateSpace)
        } action: { frame in
            cardFrames.register(frame, for: tab.id)
        }
        .onDisappear {
            cardFrames.removeFrame(for: tab.id)
        }
        .browserSplitDropCardFrame(
            tabID: isSelectedSpace ? tab.id : nil,
            assignment: isSelectedSpace ? BrowserSpaceRuntimeAssignment(space: space) : nil,
            state: sidebarInteraction.sidebarReorderState
        )
    }

    private var presentedPage: BrowserPage? {
        pages.surfacePage(for: tab.id, in: space)
    }
}
