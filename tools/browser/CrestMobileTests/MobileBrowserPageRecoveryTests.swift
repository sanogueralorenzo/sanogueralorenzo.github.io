import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserPageRecoveryTests: XCTestCase {

    // MARK: - Stopped web-content processes

    func testAStoppedWebContentProcessReachesTheCoresRecoveryBudget() throws {
        let space = makeSpace(index: 1)
        let tab = try XCTUnwrap(space.tabs.first)
        // The window shows the page's tab, so the core recovers it in view.
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let page = try openPage(in: space, through: browser)

        // The core has WebKit reload a page in view while its budget lasts.
        page.recordWebContentTermination()
        page.recordWebContentTermination()
        browser.core.drain()
        XCTAssertNil(page.live.failure)

        // Past it, the page shows the failure.
        page.recordWebContentTermination()
        browser.core.drain()
        XCTAssertEqual(page.live.failure?.error, .webContentProcessStopped)
    }

    // MARK: - App-initiated navigation marker

    func testTheAppInitiatedMarkerIsConsumedByTheNavigationItAuthorized() throws {
        let space = makeSpace(index: 4)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let page = try openPage(in: space, through: browser)
        let fileURL = URL(fileURLWithPath: "/tmp/crest-mobile-fixture.html")
        let replay = MobileReplayNavigationAction(url: fileURL)

        page.load(fileURL)
        XCTAssertTrue(
            page.isAppInitiated(replay),
            "The load Crest just asked for is app-initiated until WebKit honors it."
        )

        page.webView(page.webView, didStartProvisionalNavigation: nil)

        XCTAssertFalse(
            page.isAppInitiated(replay),
            "Web content must not be able to replay a file URL Crest once loaded."
        )
        XCTAssertEqual(
            SchemeHandling.disposition(
                for: fileURL,
                isAppInitiated: page.isAppInitiated(replay)
            ),
            .blocked
        )
    }

    /// Opens the page for `space`'s first tab through `browser`'s core, as a
    /// page store opens one. Keep `browser` alive while the page is in use.
    private func openPage(in space: SpaceState.Seed, through browser: BrowserStore) throws -> MobileBrowserPage {
        let tab = try XCTUnwrap(space.tabs.first)
        return try XCTUnwrap(
            browser.openWebKitPage(in: space.id, for: tab.id).map { opened in
                MobileBrowserPage(
                    corePage: opened.core,
                    webKitPage: opened.webKit,
                    tab: browser.pageTab(tab.id, in: space.id),
                    space: browser.hostedSpace(space.id),
                    openNewTab: { _ in }
                )
            }
        )
    }

    private func makeSpace(index: Int) -> SpaceState.Seed {
        let tab = TabState.Seed.startPage(
            id: fixedUUID(index * 10 + 1),
            placement: .current
        )
        return SpaceState.Seed(
            id: fixedUUID(index * 10 + 2),
            profileID: fixedUUID(index * 10 + 3),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }
}

/// Stands in for a navigation web content asks for while naming a URL Crest once
/// loaded itself. WebKit never lets an app build a real `WKNavigationAction`, and
/// the web source origin is what separates a replay from Crest's own load.
private final class MobileReplayNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
    private let stubRequest: URLRequest

    init(url: URL) {
        stubRequest = URLRequest(url: url)
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { .other }
    override var targetFrame: WKFrameInfo? { nil }
    var browserSourceOrigin: SiteOrigin? {
        SiteOrigin(scheme: "https", host: "replay.crest.test", port: 443)
    }
}
