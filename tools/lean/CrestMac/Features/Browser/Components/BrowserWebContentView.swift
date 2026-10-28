import SwiftUI

struct BrowserWebContentView: View {
    let page: BrowserPage
    let browser: BrowserStore
    let pages: BrowserPagePool
    var isAuthenticationPage = false

    @Environment(\.browserWebFocusRestorationGate)
    private var browserFocusRestorationGate

    var body: some View {
        VStack(spacing: 0) {

            GeometryReader { geometry in
                let layout = BrowserDeveloperViewportLayout(
                    viewport: page.developerViewport,
                    available: geometry.size
                )
                BrowserWebPageSurface(
                    page: page,
                    browser: browser,
                    pagePresentation: pagePresentation,
                    isPageActive: isAuthenticationPage || pages.commandPage === page,
                    focusRestorationGate: focusRestorationGate,
                    tabPlacement: tabPlacement(ofPage:),
                    goToSharingCounterpart: sharingCounterpartActivation
                )
                .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                .scaleEffect(layout.scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        }
        .modifier(
            BrowserPageToolbarHost {
                if page.isDeveloperModeEnabled {
                    BrowserDeveloperToolbar(
                        page: page, browser: browser, pages: pages,
                        permissionCenter: pages.permissionCenter
                    )
                }
            }
        )
        .modifier(
            BrowserTranslationHost(
                translation: page.translation, page: page,
                isActive: isShownPage,
                isLoading: page.live.isLoading,
                isReaderActive: page.readerModeState.isActive
            )
        )
    }

    /// Shows the tab at the other end of the page's tab sharing, as clicking
    /// it in the sidebar does, when Crest knows it.
    private var sharingCounterpartActivation: (() -> Void)? {
        guard let tabID = pages.tabSharingCounterpart(of: page) else { return nil }
        let browser = browser
        let pages = pages
        return {
            // Select the tab before presenting its page.
            browser.selectTab(tabID)
            pages.select()
        }
    }

    /// Where the tab holding the page `pageID` sits in its Space's tabs, and
    /// what the sidebar calls it.
    private func tabPlacement(ofPage pageID: UUID) -> BrowserShareSourceOffer.TabPlacement? {
        guard let held = pages.livePages.first(where: { $0.corePage.id == pageID }),
            let tabID = held.navigationContext?.tabID,
            let space = browser.spaceModel(held.spaceID),
            let position = space.tabs.models.firstIndex(where: { $0.id == tabID })
        else { return nil }
        return BrowserShareSourceOffer.TabPlacement(position: position, name: space.tabs.models[position].shownTitle)
    }

    private var focusRestorationGate: BrowserWebFocusRestorationGate {
        BrowserWebFocusRestorationGate(
            browserChromeOwnsFocus:
                browserFocusRestorationGate.browserChromeOwnsFocus,
            pageChromeOwnsFocus:
                page.isFindPresented
                || page.live.failure != nil
                || page.webContentFailureMessage != nil
        )
    }

    private var pagePresentation: PagePresentation {
        .of(.webPage, page: page)
    }

    private var isShownPage: Bool {
        if isAuthenticationPage { return true }
        guard pages.activePage === page, let space = browser.shownSpace else { return false }
        return space.id == page.spaceID && space.profileID == page.profileID
    }

}
