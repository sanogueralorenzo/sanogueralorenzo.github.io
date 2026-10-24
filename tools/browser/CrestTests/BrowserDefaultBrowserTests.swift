import XCTest
@testable import Crest

@MainActor
final class BrowserDefaultBrowserTests: XCTestCase {

    func testExternalURLReusesASelectedStartPageThenCreatesANewCurrentTab() throws {
        let browser = BrowserStore.privateBrowsing()
        let firstURL = try XCTUnwrap(URL(string: "https://example.com/first"))
        let secondURL = try XCTUnwrap(URL(string: "https://example.com/second"))
        let originalTabID = try XCTUnwrap(browser.shownTab?.id)

        XCTAssertTrue(browser.openExternalURL(firstURL))
        XCTAssertEqual(browser.shownTab?.id, originalTabID)
        XCTAssertEqual(browser.shownTab?.address, firstURL)
        XCTAssertEqual(browser.shownSpace?.currentTabs.count, 1)

        XCTAssertTrue(browser.openExternalURL(secondURL))
        XCTAssertNotEqual(browser.shownTab?.id, originalTabID)
        XCTAssertEqual(browser.shownTab?.address, secondURL)
        XCTAssertEqual(browser.shownSpace?.currentTabs.count, 2)
    }

    func testDefaultBrowserControllerOwnsExplicitStatusAndRequestFlow() async {
        var isSystemDefault = false
        var requestCount = 0
        let controller = BrowserDefaultBrowserController(
            requestStyle: .direct,
            statusCheck: { isSystemDefault },
            defaultRequest: {
                requestCount += 1
                isSystemDefault = true
            },
            settingsOpener: {}
        )

        XCTAssertEqual(controller.status, .unknown)
        controller.refreshStatus()
        XCTAssertEqual(controller.status, .notDefault)

        await controller.requestDefault()

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(controller.status, .isDefault)
        XCTAssertFalse(controller.isWorking)
    }
}
