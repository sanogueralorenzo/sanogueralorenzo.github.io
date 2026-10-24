import AppKit
import WebKit
import XCTest

@testable import Crest

final class BrowserVisitedLinkStylerTests: XCTestCase {
    func testVisitedURLPayloadUsesOnlyNormalizedWebHistory() throws {
        let history = [
            HistoryEntryState(
                url: try XCTUnwrap(URL(string: "https://arc.net/#download")),
                title: "Arc",
                firstVisitedAt: .now,
                lastVisitedAt: .now
            ),
            HistoryEntryState(
                url: try XCTUnwrap(URL(string: "file:///tmp/private")),
                title: "Local",
                firstVisitedAt: .now,
                lastVisitedAt: .now
            ),
        ]

        XCTAssertEqual(
            BrowserVisitedLinkStyler.normalizedVisitedURLStrings(history),
            ["https://arc.net/"]
        )
    }

    @MainActor
    func testStylerHighlightsAMatchingLinkWithoutExposingHistoryToThePage() async throws {
        let webView = try await webView(
            html:
                """
                <style>
                  a:link { color: rgb(12, 34, 56); }
                  a:visited { color: rgb(184, 140, 255); }
                </style>
                <a id="result" href="https://example.com/visited?utm_source=crest">
                  Visited result
                </a>
                """,
            baseURL: try XCTUnwrap(URL(string: "https://news.example.org/article"))
        )
        let originalStyle = try await styleAttribute(of: "#result", in: webView)
        let visitedURL = try XCTUnwrap(
            URL(string: "https://example.com/visited?utm_source=crest")
        )

        await BrowserVisitedLinkStyler.apply(
            history: [
                HistoryEntryState(
                    url: visitedURL,
                    title: "Visited result",
                    firstVisitedAt: .now,
                    lastVisitedAt: .now
                )
            ],
            to: webView
        )

        let computedColor = try await computedColor(of: "#result", in: webView)
        let finalStyle = try await styleAttribute(of: "#result", in: webView)
        let pageWorldHistoryGlobalType = try await pageWorldHistoryGlobalType(in: webView)
        let pageWorldContainsHighlight = try await pageWorldContainsCrestHighlight(in: webView)
        let pageWorldMatchesVisited = try await pageWorldMatchesVisited(
            selector: "#result",
            in: webView
        )
        XCTAssertTrue(BrowserVisitedLinkStyler.containsVisitedURL(visitedURL, in: webView))
        XCTAssertEqual(computedColor, "rgb(12, 34, 56)")
        XCTAssertEqual(finalStyle, originalStyle)
        XCTAssertEqual(pageWorldHistoryGlobalType, "undefined")
        XCTAssertFalse(pageWorldContainsHighlight)
        XCTAssertFalse(pageWorldMatchesVisited)
    }

    @MainActor
    func testVisitedStateIsIsolatedBetweenWebViews() async throws {
        let workWebView = try await webView(
            html: "<a href=\"https://example.com/visited\">Work link</a>",
            baseURL: try XCTUnwrap(URL(string: "https://work.example.org/"))
        )
        let personalWebView = try await webView(
            html: "<a href=\"https://example.com/visited\">Personal link</a>",
            baseURL: try XCTUnwrap(URL(string: "https://personal.example.org/"))
        )
        let visitedURL = try XCTUnwrap(URL(string: "https://example.com/visited"))

        await BrowserVisitedLinkStyler.apply(
            history: [
                HistoryEntryState(
                    url: visitedURL,
                    title: "Visited result",
                    firstVisitedAt: .now,
                    lastVisitedAt: .now
                )
            ],
            to: workWebView
        )

        XCTAssertTrue(BrowserVisitedLinkStyler.containsVisitedURL(visitedURL, in: workWebView))
        XCTAssertFalse(
            BrowserVisitedLinkStyler.containsVisitedURL(visitedURL, in: personalWebView)
        )
    }

    @MainActor
    private func webView(html: String, baseURL: URL) async throws -> WKWebView {
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        let navigation = VisitedLinkNavigationWaiter(webView: webView)
        webView.navigationDelegate = navigation
        webView.loadHTMLString(html, baseURL: baseURL)
        try await navigation.waitForCompletion()
        return webView
    }

    @MainActor
    private func computedColor(of selector: String, in webView: WKWebView) async throws
        -> String?
    {
        try await webView.callAsyncJavaScript(
            "return getComputedStyle(document.querySelector(selector)).color",
            arguments: ["selector": selector],
            in: nil,
            contentWorld: .page
        ) as? String
    }

    @MainActor
    private func styleAttribute(of selector: String, in webView: WKWebView) async throws
        -> String?
    {
        try await webView.callAsyncJavaScript(
            "return document.querySelector(selector).getAttribute('style')",
            arguments: ["selector": selector],
            in: nil,
            contentWorld: .page
        ) as? String
    }

    @MainActor
    private func pageWorldHistoryGlobalType(in webView: WKWebView) async throws -> String? {
        try await webView.callAsyncJavaScript(
            "return typeof globalThis.__crestVisitedURLs",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String
    }

    @MainActor
    private func pageWorldContainsCrestHighlight(in webView: WKWebView) async throws -> Bool {
        try await webView.callAsyncJavaScript(
            "return CSS.highlights?.has('crest-visited') ?? false",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Bool ?? false
    }

    @MainActor
    private func pageWorldMatchesVisited(selector: String, in webView: WKWebView) async throws
        -> Bool
    {
        try await webView.callAsyncJavaScript(
            "return document.querySelector(selector).matches(':visited')",
            arguments: ["selector": selector],
            in: nil,
            contentWorld: .page
        ) as? Bool ?? false
    }

}

@MainActor
private final class VisitedLinkNavigationWaiter: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?

    init(webView: WKWebView) {
        self.webView = webView
    }

    func waitForCompletion() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
