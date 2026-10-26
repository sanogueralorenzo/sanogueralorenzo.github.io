import XCTest

@testable import CrestMobile

@MainActor
final class MobileTransientBrowsingTests: XCTestCase {
    func testMobileCrossSpaceMoveRebuildsTheTabWithTheDestinationProfile() throws {
        let browser = BrowserStore.hostingPages(SessionState.Seed.preview)
        let source = try XCTUnwrap(browser.spaceModels.first)
        let destination = try XCTUnwrap(browser.spaceModels.last)
        let tab = try XCTUnwrap(source.currentTabs.first)
        browser.activateSessionTab(tab.id, in: source.id)
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)

        pages.select()
        let sourcePage = try XCTUnwrap(pages.activePage)
        XCTAssertEqual(sourcePage.spaceID, source.id)

        XCTAssertTrue(
            browser.moveTab(tab.id, from: source.id, into: destination.id)
        )
        pages.reconcile()
        browser.activateSessionTab(tab.id, in: destination.id)
        pages.select()

        let destinationPage = try XCTUnwrap(pages.activePage)
        XCTAssertFalse(sourcePage === destinationPage)
        XCTAssertEqual(destinationPage.spaceID, destination.id)
        XCTAssertEqual(destinationPage.profileID, destination.profileID)
        XCTAssertFalse(
            sourcePage.webView.configuration.websiteDataStore
                === destinationPage.webView.configuration.websiteDataStore
        )
        XCTAssertFalse(destinationPage.webView.configuration.websiteDataStore.isPersistent)
    }

}
