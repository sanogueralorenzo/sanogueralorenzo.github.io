import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageNavigationMarkerTests: XCTestCase {
    /// The pool of the page a test drives, which keeps its window and
    /// workspace open: a workspace that closes takes its pages with it.
    private var pool: BrowserPagePool?

    func testSameDocumentNavigationRetiresPendingURLAcrossHistoryTraversal() async throws {
        let page = try makePage()
        defer { page.release(keepingState: false) }
        let root = try XCTUnwrap(URL(string: "https://history.crest.test/feed"))
        let post = try XCTUnwrap(URL(string: "https://history.crest.test/post"))
        page.webView.loadSimulatedRequest(
            URLRequest(url: root), responseHTML: "<html><title>Feed</title><body>Feed</body></html>")
        try await waitForNavigation { page.completedNavigationCount == 1 }
        let commits = page.committedNavigationCount

        // A site may intercept an allowed link and finish it in the existing
        // document. No didFinish callback will retire its pending destination.
        page.prepareForNavigation(to: post)
        _ = try await page.webView.evaluateJavaScript("history.pushState({}, '', '/post')")
        // The core hears the address and the retired destination once the
        // engine's history settles, which can be a turn after the address.
        try await waitForNavigation { page.live.documentURL == post && page.live.pendingNavigationURL == nil }
        XCTAssertNil(page.live.pendingNavigationURL)
        XCTAssertEqual(page.live.displayURL, post)
        XCTAssertEqual(page.backHistory.map(\.url), page.webView.backForwardList.backList.reversed().map(\.url))

        _ = try await page.webView.evaluateJavaScript("history.back()")
        try await waitForNavigation { page.live.documentURL == root }
        XCTAssertEqual(page.live.displayURL, root)
        XCTAssertEqual(page.committedNavigationCount, commits)

        _ = try await page.webView.evaluateJavaScript("history.forward()")
        try await waitForNavigation { page.live.documentURL == post }
        _ = try await page.webView.evaluateJavaScript("history.replaceState({}, '', '/updated-post')")
        let replaced = try XCTUnwrap(URL(string: "https://history.crest.test/updated-post"))
        try await waitForNavigation { page.live.documentURL == replaced && page.live.pendingNavigationURL == nil }
        XCTAssertEqual(page.live.displayURL, replaced)
        XCTAssertNil(page.live.pendingNavigationURL)
    }

    func testLinkHistoryRetainsSameDocumentEntriesAndDiscardsForwardBranch() async throws {
        let page = try makePage()
        defer { page.release(keepingState: false) }
        let root = try XCTUnwrap(URL(string: "https://history.crest.test/root"))
        page.webView.loadSimulatedRequest(
            URLRequest(url: root), responseHTML: "<html><title>History</title><body>History</body></html>")
        try await waitForNavigation { page.completedNavigationCount == 1 }
        let feed = try XCTUnwrap(URL(string: "https://history.crest.test/feed"))
        let post = try XCTUnwrap(URL(string: "https://history.crest.test/post"))
        for destination in [feed, post] {
            page.navigationHistory.recordLink(to: destination, in: page.webView.backForwardList)
            page.prepareForNavigation(to: destination)
            _ = try await page.webView.evaluateJavaScript("history.pushState({}, '', '\(destination.path)')")
            try await waitForNavigation { page.live.documentURL == destination }
        }
        XCTAssertEqual(page.backHistory.map(\.url), [feed, root])
        // Every entry keeps the identity the core knows it by however the
        // page moves through them, so the menus never drift from WebKit's list.
        let identities = page.backHistory.reversed().map(\.id)
        page.goBack()
        try await waitForNavigation { page.live.documentURL == feed }
        XCTAssertEqual(page.live.displayURL, feed)
        XCTAssertEqual(page.forwardHistory.map(\.url), [post])
        page.goToHistory(try XCTUnwrap(page.forwardHistory.first))
        try await waitForNavigation { page.live.documentURL == post }
        page.goToHistory(try XCTUnwrap(page.backHistory.last))
        try await waitForNavigation { page.live.documentURL == root }
        XCTAssertEqual(page.forwardHistory.map(\.url), [feed, post])
        XCTAssertEqual([identities[0]] + page.forwardHistory.prefix(1).map(\.id), identities)
        page.goForward()
        try await waitForNavigation { page.live.documentURL == feed }

        // Replacing the current entry must not create a duplicate. A new link
        // after Back must discard the old forward branch, even for equal URLs.
        _ = try await page.webView.evaluateJavaScript("history.replaceState({}, '', '/updated-feed')")
        let updated = try XCTUnwrap(URL(string: "https://history.crest.test/updated-feed"))
        try await waitForNavigation { page.live.documentURL == updated }
        XCTAssertEqual(page.backHistory.map(\.url), [root])
        page.navigationHistory.recordLink(to: root, in: page.webView.backForwardList)
        page.prepareForNavigation(to: root)
        _ = try await page.webView.evaluateJavaScript("history.pushState({}, '', '/root')")
        try await waitForNavigation { page.live.documentURL == root }
        XCTAssertEqual(page.backHistory.map(\.url), [updated, root])
        XCTAssertTrue(page.forwardHistory.isEmpty)

        // A replacement document returns ownership to WebKit's native list;
        // supplemental same-document items must not become obsolete targets.
        let replacement = try XCTUnwrap(URL(string: "https://history.crest.test/new-document"))
        page.webView.loadSimulatedRequest(
            URLRequest(url: replacement), responseHTML: "<html><body>New document</body></html>")
        try await waitForNavigation { page.completedNavigationCount == 2 }
        XCTAssertEqual(page.backHistory.map(\.url), page.webView.backForwardList.backList.reversed().map(\.url))
    }

    func testForwardReturnsToThePageAScriptOpenedAfterGoingBack() async throws {
        // WebKit stops listing an entry a script created without user
        // activation once the page leaves it, and its canGoForward follows.
        let server = try BrowserPrivacyHTTPServer()
        server.overrideResponse = { request in
            let script =
                request.path == "/start"
                ? """
                <script>
                if (!sessionStorage.getItem('left')) {
                  sessionStorage.setItem('left', '1');
                  setTimeout(() => { location.href = '/next'; }, 100);
                }
                </script>
                """ : ""
            return (
                "200 OK", "Content-Type: text/html\r\n",
                Data("<html><title>\(request.path)</title><body>\(script)</body></html>".utf8)
            )
        }
        try await server.start()
        defer { server.stop() }
        let page = try makePage()
        defer { page.release(keepingState: false) }
        let start = server.url(host: "127.0.0.1", path: "/start")
        let next = server.url(host: "127.0.0.1", path: "/next")
        page.load(start)
        try await waitForNavigation { page.live.documentURL == next && !page.live.isLoading }

        page.goBack()
        try await waitForNavigation { page.live.documentURL == start && !page.live.isLoading }
        // The core hears the history with the page's next snapshot, which can
        // be a turn after the address.
        try await waitForNavigation { page.live.canGoForward }
        XCTAssertEqual(page.forwardHistory.map(\.url), [next])

        page.goForward()
        try await waitForNavigation { page.live.documentURL == next && !page.live.isLoading }
        try await waitForNavigation { !page.live.canGoForward }
        XCTAssertEqual(page.backHistory.map(\.url), [start])
    }

    private func waitForNavigation(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), "The expected navigation did not settle.")
    }

    func testTheAppInitiatedMarkerIsConsumedByTheNavigationItAuthorized() throws {
        let page = try makePage()
        let fileURL = URL(fileURLWithPath: "/tmp/crest-desktop-fixture.html")
        let replay = ReplayNavigationAction(url: fileURL)

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

    func testARestoredInteractionStateMarkerIsConsumedTheSameWay() throws {
        let page = try makePage()
        let fileURL = URL(fileURLWithPath: "/tmp/crest-desktop-restored.html")
        let replay = ReplayNavigationAction(url: fileURL)

        // WebKit refuses random state, which is enough here: the marker is set
        // before the state is installed either way.
        _ = page.restoreInteractionState(
            Data((0..<256).map { _ in UInt8.random(in: 0...255) }),
            expecting: fileURL
        )
        XCTAssertTrue(page.isAppInitiated(replay))

        page.webView(page.webView, didStartProvisionalNavigation: nil)

        XCTAssertFalse(page.isAppInitiated(replay))
    }

    private func makePage() throws -> BrowserPage {
        let tab = TabState.Seed.startPage()
        let space = SpaceState.Seed(
            name: "Marker",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
        let pool = BrowserPagePool(browser: .hostingPages(SessionState.Seed(spaces: [space])))
        self.pool = pool
        pool.present(tab: tab.id, in: space.id)
        return try XCTUnwrap(pool.activePage)
    }

}

/// Stands in for a navigation web content asks for while naming a URL Crest once
/// loaded itself. WebKit never lets an app build a real `WKNavigationAction`, and
/// the web source origin is what separates a replay from Crest's own load.
private final class ReplayNavigationAction: WKNavigationAction,
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
