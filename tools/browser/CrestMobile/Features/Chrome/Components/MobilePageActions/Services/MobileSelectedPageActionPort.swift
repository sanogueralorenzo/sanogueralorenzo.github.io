import Foundation

@MainActor
struct MobileSelectedPageActionPort: MobilePageActions {
    private let browser: BrowserStore
    private let pages: MobileBrowserPageStore
    private let spaceAccess: BrowserSpaceAccessController
    private let expectedAssignment: BrowserTabRuntimeAssignment

    init?(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        spaceAccess: BrowserSpaceAccessController
    ) {
        guard let assignment = browser.shownTabAssignment else { return nil }
        self.init(browser: browser, pages: pages, spaceAccess: spaceAccess, expectedAssignment: assignment)
    }

    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        spaceAccess: BrowserSpaceAccessController,
        expectedAssignment: BrowserTabRuntimeAssignment
    ) {
        self.browser = browser
        self.pages = pages
        self.spaceAccess = spaceAccess
        self.expectedAssignment = expectedAssignment
    }

    var isAvailable: Bool {
        activePage != nil
    }

    var pageAssignment: BrowserTabRuntimeAssignment? {
        isAvailable ? expectedAssignment : nil
    }

    var activePage: MobileBrowserPage? {
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space),
            browser.shownTabAssignment == expectedAssignment,
            let page = pages.activePage,
            page.tabID == expectedAssignment.tabID,
            page.spaceID == expectedAssignment.spaceID,
            page.profileID == expectedAssignment.profileID
        else { return nil }
        return page
    }

    var activeURL: URL? {
        activePage?.live.displayURL
    }

    var canGoBack: Bool {
        activePage?.live.canGoBack == true
    }

    var canGoForward: Bool {
        activePage?.live.canGoForward == true
    }

    var backHistory: [BrowserNavigationHistoryItem] {
        activePage?.backHistory ?? []
    }

    var forwardHistory: [BrowserNavigationHistoryItem] {
        activePage?.forwardHistory ?? []
    }

    var preferredContentModeActionTitle: LocalizedStringResource {
        activePage?.isRequestingDesktopSite == true
            ? "Request Mobile Website"
            : "Request Desktop Website"
    }

    var readerModeActionTitle: LocalizedStringResource {
        readerModeState.actionTitle
    }

    var readerModeState: BrowserReaderModeState {
        activePage?.readerModeState ?? .unavailable
    }

    var pageZoomLabel: String {
        (activePage?.pageZoom ?? 1).pageZoomPercentage
    }

    var blockedPopupNotice: BrowserBlockedPopupNotice? {
        activePage?.blockedPopupNotice
    }

    func goBack() {
        activePage?.goBack()
    }

    func goForward() {
        activePage?.goForward()
    }

    func goBack(to item: BrowserNavigationHistoryItem) {
        activePage?.goToHistory(item)
    }

    func goForward(to item: BrowserNavigationHistoryItem) {
        activePage?.goToHistory(item)
    }

    func reloadOrStop() {
        activePage?.reloadOrStop()
    }

    func reload() {
        activePage?.reload()
    }

    func stopLoading() {
        activePage?.stopLoading()
    }

    func reloadFromOrigin() {
        activePage?.performReload(.fromOrigin)
    }

    func clearSiteDataAndReload() async {
        await activePage?.clearSiteDataAndReload()
    }

    func togglePreferredContentMode() {
        activePage?.togglePreferredContentMode()
    }

    func toggleReaderMode() {
        activePage?.toggleReaderMode()
    }

    func presentFind() {
        activePage?.presentFind()
    }

    func zoomIn() {
        guard activePage != nil else { return }
        pages.zoomIn()
    }

    func zoomOut() {
        guard activePage != nil else { return }
        pages.zoomOut()
    }

    func resetZoom() {
        guard activePage != nil else { return }
        pages.resetZoom()
    }

    func allowAutomaticPopupsForBlockedSite() {
        activePage?.allowAutomaticPopupsForBlockedSite()
    }

    @discardableResult
    func copyPageLink() -> Bool {
        guard isAvailable else { return false }
        return pages.copyPageLink()
    }

    @discardableResult
    func copyPageLinkAsMarkdown() -> Bool {
        guard isAvailable else { return false }
        return pages.copyPageLinkAsMarkdown()
    }

    func printPage() {
        activePage?.printPage()
    }

    func exportPDF(to destination: MobileBrowserFileExportDestination) {
        activePage?.exportPDF(to: destination)
    }

    func exportWebArchive(to destination: MobileBrowserFileExportDestination) {
        activePage?.exportWebArchive(to: destination)
    }

    func reconcileContentBlocking() async {
        await pages.reconcileContentBlocking()
    }
}
