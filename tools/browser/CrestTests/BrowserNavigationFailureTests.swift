import AppKit
import SwiftUI
import WebKit
import XCTest

@testable import Crest

final class BrowserNavigationFailureClassificationTests: XCTestCase {
    func testClassifiesCommonConnectionFailuresWithStableDiagnostics() throws {
        let url = try XCTUnwrap(URL(string: "https://status.example.test/report"))

        let timeout = try XCTUnwrap(
            PageFailure(error: URLError(.timedOut), replacedDocument: false, fallbackURL: url)
        )
        XCTAssertEqual(timeout.error, .timedOut)
        XCTAssertEqual(timeout.failingURL, url)
        XCTAssertEqual(timeout.error.code, "CREST_TIMED_OUT")
        XCTAssertEqual(timeout.domain, NSURLErrorDomain)
        XCTAssertEqual(timeout.code, Int64(URLError.timedOut.rawValue))

        let offline = try XCTUnwrap(
            PageFailure(error: URLError(.notConnectedToInternet), replacedDocument: false, fallbackURL: url)
        )
        XCTAssertEqual(offline.error, .offline)
        XCTAssertEqual(offline.error.code, "CREST_INTERNET_DISCONNECTED")

        let secureConnection = try XCTUnwrap(
            PageFailure(error: URLError(.serverCertificateUntrusted), replacedDocument: false, fallbackURL: url)
        )
        XCTAssertEqual(secureConnection.error, .secureConnectionFailed)
        XCTAssertEqual(secureConnection.error.code, "CREST_CERTIFICATE_INVALID")
    }

    func testUsesTheFailingURLReportedByURLLoading() throws {
        let fallbackURL = try XCTUnwrap(URL(string: "https://fallback.example.test"))
        let failingURL = try XCTUnwrap(URL(string: "https://actual.example.test/path"))
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.cannotFindHost.rawValue,
            userInfo: [NSURLErrorFailingURLErrorKey: failingURL]
        )

        let failure = try XCTUnwrap(PageFailure(error: error, replacedDocument: false, fallbackURL: fallbackURL))

        XCTAssertEqual(failure.error, .cannotFindServer)
        XCTAssertEqual(failure.failingURL, failingURL)
        XCTAssertEqual(failure.displayHost, "actual.example.test")
    }

    func testIgnoresExpectedNavigationInterruptions() {
        XCTAssertNil(
            PageFailure(
                error: URLError(.cancelled), replacedDocument: false, fallbackURL: URL(string: "https://example.test"))
        )
        XCTAssertNil(
            PageFailure(
                error: NSError(domain: "WebKitErrorDomain", code: 102), replacedDocument: false,
                fallbackURL: URL(string: "https://example.test"))
        )
        XCTAssertNil(
            PageFailure(
                error: WKError(.webContentProcessTerminated), replacedDocument: true,
                fallbackURL: URL(string: "https://example.test"))
        )
    }
}

/// A WebKit page's failures, redirects and hand-offs reach the core, which
/// holds what the page shows; each check waits for the core to publish it.
@MainActor
final class BrowserPageNavigationFailureTests: XCTestCase {
    private var navigationSource: WKWebView?
    /// The window the page belongs to and its pool, kept while the test runs
    /// so its workspace stays attached to the core.
    private var browser: BrowserStore?
    private var pool: BrowserPagePool?

    func testDesktopPagePublishesAndRetriesAProvisionalFailure() async throws {
        let page = try makePage()
        let failingURL = try XCTUnwrap(URL(string: "https://offline.example.test/path"))
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.cannotConnectToHost.rawValue,
            userInfo: [NSURLErrorFailingURLErrorKey: failingURL]
        )

        page.webView(
            page.webView,
            didFailProvisionalNavigation: nil,
            withError: error
        )

        try await waitUntil { page.live.failure != nil }
        XCTAssertEqual(page.live.failure?.error, .cannotConnect)
        XCTAssertEqual(page.live.failure?.replacedDocument, false)
        XCTAssertEqual(page.live.displayURL, failingURL)
        XCTAssertFalse(page.canReturnFromNavigationFailure)

        page.retryAfterNavigationFailure()

        XCTAssertNil(page.live.failure)
        XCTAssertEqual(page.live.pendingNavigationURL, failingURL)
        XCTAssertEqual(page.live.displayURL, failingURL)
    }

    func testDesktopPageIgnoresAFailureFromASupersededNavigation() async throws {
        let page = try makePage()
        let superseded = try makeNavigation()
        let current = try makeNavigation()

        page.webView(page.webView, didStartProvisionalNavigation: superseded)
        page.webView(page.webView, didStartProvisionalNavigation: current)
        page.webView(
            page.webView,
            didFailProvisionalNavigation: superseded,
            withError: URLError(.cannotConnectToHost)
        )
        await settle()

        XCTAssertNil(page.live.failure)
    }

    func testDesktopPageFollowsAServerRedirectInTheDisplayedURL() async throws {
        let page = try makePage()
        let requestedURL = try XCTUnwrap(URL(string: "https://short.example.test/start"))
        let redirectedURL = try XCTUnwrap(URL(string: "https://destination.example.test/final"))
        let navigation = try makeNavigation()
        // WebKit reports this navigation through a web view that answers the
        // address it loads. The page's own web view loads nothing, so no real
        // navigation of it can start after this one and replace it.
        let reportingWebView = ReportingWebViewStub(frame: .zero, configuration: WKWebViewConfiguration())
        reportingWebView.reportedURL = requestedURL
        page.webView(reportingWebView, didStartProvisionalNavigation: navigation)

        try await waitUntil { page.live.pendingNavigationURL == requestedURL }
        XCTAssertEqual(page.live.displayURL, requestedURL)

        reportingWebView.reportedURL = redirectedURL
        page.webView(reportingWebView, didReceiveServerRedirectForProvisionalNavigation: navigation)

        try await waitUntil { page.live.pendingNavigationURL == redirectedURL }
        XCTAssertEqual(page.live.displayURL, redirectedURL)
    }

    func testDesktopPageHandsOffAnExternalSchemeWithoutAnErrorPage() async throws {
        let page = try makePage()
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))
        let recorder = PolicyRecorder()

        // A scripted trigger keeps this test from launching a real mail client:
        // the hand-off is refused before anything reaches the system, and the
        // cancel that WebKit sees is the same one a user-approved hand-off uses.
        page.webView(
            page.webView,
            decidePolicyFor: StubExternalNavigationAction(
                url: mailURL,
                navigationType: .other
            )
        ) { recorder.policy = $0 }

        XCTAssertEqual(recorder.policy, .cancel)

        // WebKit answers a policy cancel with a frame-load interruption, which
        // must never become one of Crest's error pages.
        page.webView(
            page.webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: "WebKitErrorDomain", code: 102)
        )
        await settle()

        XCTAssertNil(page.live.pendingNavigationURL)
        XCTAssertNil(page.live.failure)
        XCTAssertNil(page.live.displayURL)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { return XCTFail("Timed out waiting for the core") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Lets the page report what it shows and the core publish it: a few
    /// turns of the main queue.
    private func settle() async {
        for _ in 0..<5 { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// Mints a real navigation object. WebKit owns navigation identity, so the
    /// tests drive the delegate with navigations a web view actually created.
    private func makeNavigation() throws -> WKNavigation {
        let source =
            navigationSource
            ?? WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        navigationSource = source
        return try XCTUnwrap(source.loadHTMLString("<html></html>", baseURL: nil))
    }

    private func makePage() throws -> BrowserPage {
        let tab = TabState.Seed(title: "Blank", url: nil, placement: .current)
        let space = SpaceState.Seed(
            name: "Test",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        self.browser = browser
        let pool = BrowserPagePool(browser: browser)
        self.pool = pool
        pool.present(tab: tab.id, in: space.id)
        return try XCTUnwrap(pool.activePage)
    }
}

/// A web view that answers the address its navigation reached, as WebKit's
/// does while a provisional navigation starts and follows a redirect.
private final class ReportingWebViewStub: WKWebView {
    var reportedURL: URL?

    override var url: URL? { reportedURL }
}

/// WebKit never lets an app build a real `WKNavigationAction`, so the external
/// hand-off test stands in for the one WebKit hands to the policy delegate.
private final class StubExternalNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
    private let stubRequest: URLRequest
    private let stubNavigationType: WKNavigationType

    init(url: URL, navigationType: WKNavigationType) {
        stubRequest = URLRequest(url: url)
        stubNavigationType = navigationType
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { stubNavigationType }
    override var targetFrame: WKFrameInfo? { nil }
    var browserSourceOrigin: SiteOrigin? { nil }
}

/// A `@Sendable` decision handler cannot capture a mutable local, so the policy
/// WebKit is handed lands in a box the test can read afterwards.
@MainActor
private final class PolicyRecorder {
    var policy: WKNavigationActionPolicy?
}
