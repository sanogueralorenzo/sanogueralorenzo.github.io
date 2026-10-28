import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageEngineMoveTests: XCTestCase {
    /// Recreating a WebKit page keeps the tab identity, replaces its view,
    /// and retires the previous view's delegates before loading the replacement.
    func testRecreatedPageKeepsItsIdentityAndHostsTheReplacementView() async throws {
        let tab = TabState.Seed(title: "Moving", url: nil, placement: .current)
        let space = SpaceState.Seed(
            id: UUID(), profileID: UUID(), name: "Moves", folders: [], tabs: [tab])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let pool = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        pool.present(tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        let corePage = page.corePage
        let engines = browser.core.engines
        let leftView = try XCTUnwrap(page.webKitView)

        // The previous physical page closes while the logical page remains.
        engines.run(.closePage(ClosePage(pageID: corePage.id, keepsState: false)))
        XCTAssertTrue(engines.page(corePage.id) === corePage, "A page moving on is still the core's page.")

        // A recreated page is handed to its existing host before loading.
        engines.run(
            .createPage(
                CreatePage(
                    pageID: corePage.id, profileID: space.profileID, isPrivate: false, windowID: browser.windowID,
                    restoreState: nil)))
        let movedView = try XCTUnwrap(page.webKitView)
        XCTAssertFalse(movedView === leftView)
        XCTAssertNil(leftView.navigationDelegate, "The engine the page left no longer hosts it.")
        XCTAssertTrue(pool.activePage === page)
        XCTAssertTrue(pool.presentedPage(for: tab.id) === page)
        XCTAssertTrue(page.nativeView === movedView)

        engines.run(.loadPage(LoadPage(pageID: corePage.id, url: "about:blank", entryID: nil)))
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while movedView.url == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(movedView.url?.absoluteString, "about:blank")
        XCTAssertNil(leftView.url)
    }
}
