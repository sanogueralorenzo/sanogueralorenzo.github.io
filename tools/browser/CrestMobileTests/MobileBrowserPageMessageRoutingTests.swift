import WebKit
import XCTest

@testable import CrestMobile

/// A popup shares its opener's `WKUserContentController`, so the opener's user
/// scripts run inside the popup's document and post to the opener's handlers.
/// These cover the sender-identity guard that keeps a page from acting on — and
/// attributing — another web view's messages.
@MainActor
final class MobileBrowserPageMessageRoutingTests: XCTestCase {
    func testCredentialMessagesFromAWebViewSharingTheBridgeAreIgnored() async throws {
        let space = makeSpace(index: 1)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let page = try openPage(in: space, through: browser)
        page.webView.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: "https://opener.crest.test/home"))),
            responseHTML: "<!doctype html><p>Opener</p>"
        )
        try await waitUntil { page.completedNavigationCount == 1 }

        // WebKit hands a popup a copy of its opener's configuration, and the copy
        // keeps the very same user content controller.
        let popup = WKWebView(frame: .zero, configuration: page.webView.configuration)
        XCTAssertTrue(
            popup.configuration.userContentController
                === page.webView.configuration.userContentController
        )
        let recorder = MobileRoutingNavigationRecorder()
        popup.navigationDelegate = recorder
        popup.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: "https://login.crest.test/oauth"))),
            responseHTML: Self.loginDocument
        )
        try await waitUntil { recorder.finishedNavigationCount == 1 }

        let didCapture = try await popup.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.captureForTesting(selector) === true;",
            arguments: ["selector": "#popup-login"],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        XCTAssertEqual(
            didCapture as? Bool,
            true,
            "The opener's user script does run inside the popup — that is the routing hazard."
        )
        _ = try await popup.callAsyncJavaScript(
            "document.querySelector('#popup-login').remove(); return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertNil(
            page.credentialSaveCandidate,
            "A popup's form submission must not be attributed to the opener page."
        )
        XCTAssertNil(page.credentialFillRequest)
    }

    func testAPageStillHandlesCredentialMessagesFromItsOwnWebView() async throws {
        let space = makeSpace(index: 2)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let page = try openPage(in: space, through: browser)
        page.webView.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: "https://login.crest.test/oauth"))),
            responseHTML: Self.loginDocument
        )
        try await waitUntil { page.completedNavigationCount == 1 }

        let didCapture = try await page.webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.captureForTesting(selector) === true;",
            arguments: ["selector": "#popup-login"],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        XCTAssertEqual(didCapture as? Bool, true)
        _ = try await page.webView.callAsyncJavaScript(
            "document.querySelector('#popup-login').remove(); return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil { page.credentialSaveCandidate != nil }

        XCTAssertEqual(page.credentialSaveCandidate?.username, "person@example.com")
        page.dismissCredentialSaveCandidate()
    }

    private static let loginDocument = """
        <!doctype html>
        <style>input { display: block; width: 220px; height: 32px; }</style>
        <form id="popup-login">
          <input autocomplete="username" value="person@example.com">
          <input type="password" autocomplete="current-password" value="popup-secret">
          <button type="button">Sign In</button>
        </form>
        """

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

    private func waitUntil(
        timeout: Duration = .seconds(8),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the browser state to change.")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }
}

/// Reports when a bare web view standing in for an adopted popup has finished
/// loading, so a test never races the document it is about to script.
@MainActor
private final class MobileRoutingNavigationRecorder: NSObject, WKNavigationDelegate {
    private(set) var finishedNavigationCount = 0

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        finishedNavigationCount += 1
    }
}
