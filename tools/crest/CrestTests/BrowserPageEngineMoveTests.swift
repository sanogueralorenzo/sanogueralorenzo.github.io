import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageEngineMoveTests: XCTestCase {
    /// A page the core moves to another engine closes on the engine it left
    /// and stays the core's, and the page hosting it takes the new engine's
    /// view in place: its tab keeps the same page, and the new engine's first
    /// load reaches the new view. WebKit stands in for the engine the page
    /// moves to, which builds the page anew as any other engine would.
    func testAMovedPageKeepsItsIdentityAndHostsTheNewEnginesView() async throws {
        let tab = TabState.Seed(title: "Moving", url: nil, placement: .current)
        let space = SpaceState.Seed(
            id: UUID(), profileID: UUID(), name: "Moves", symbol: "arrow.left.arrow.right",
            accent: .teal, folders: [], tabs: [tab])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let pool = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        pool.present(tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        let corePage = page.corePage
        let engines = browser.core.engines
        let leftView = try XCTUnwrap(page.webKitView)

        // The core closes the page on the engine it leaves.
        engines.run(.closePage(ClosePage(pageID: corePage.id, keepsState: false)), on: .webKit)
        XCTAssertTrue(engines.page(corePage.id) === corePage, "A page moving on is still the core's page.")

        // It creates the page on the engine it moves to, which hands the page
        // what it built before the core loads it.
        engines.run(
            .createPage(
                CreatePage(
                    pageID: corePage.id, profileID: space.profileID, isPrivate: false, windowID: browser.windowID,
                    restoreState: nil)),
            on: .webKit)
        let movedView = try XCTUnwrap(page.webKitView)
        XCTAssertFalse(movedView === leftView)
        XCTAssertNil(leftView.navigationDelegate, "The engine the page left no longer hosts it.")
        XCTAssertTrue(pool.activePage === page)
        XCTAssertTrue(pool.presentedPage(for: tab.id) === page)
        XCTAssertTrue(page.nativeView === movedView)

        engines.run(.loadPage(LoadPage(pageID: corePage.id, url: "about:blank", entryID: nil)), on: .webKit)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while movedView.url == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(movedView.url?.absoluteString, "about:blank")
        XCTAssertNil(leftView.url)
    }
}
