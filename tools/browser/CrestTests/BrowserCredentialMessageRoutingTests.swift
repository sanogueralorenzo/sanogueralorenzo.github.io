import WebKit
import XCTest

@testable import Crest

/// A popup shares its opener's `WKUserContentController`, so the opener's user
/// scripts run inside the popup's document and post to the opener's handlers.
/// These cover the sender-identity guard that keeps a page from acting on — and
/// attributing — another web view's messages.
@MainActor
final class BrowserCredentialMessageRoutingTests: XCTestCase {
    func testCredentialMessagesFromAWebViewSharingTheBridgeAreIgnored() async throws {
        let page = try makePage()
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
        let recorder = CredentialRoutingNavigationRecorder()
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
        let page = try makePage()
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

    func testPageFillsTheRequestedPasswordFieldAndRevocationRejectsFurtherFills() async throws {
        let page = try makePage()
        page.webView.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: "https://login.crest.test/oauth"))),
            responseHTML: Self.loginDocument
        )
        try await waitUntil { page.completedNavigationCount == 1 }
        let request = try await focusPassword(in: page)
        let credential = BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: page.spaceID, origin: request.origin,
                username: "saved@example.com", createdAt: .now
            ),
            password: "saved-secret"
        )

        try await page.fillCredential(credential, for: request.id)
        XCTAssertNil(page.credentialFillRequest)
        let filled =
            try await page.webView.evaluateJavaScript(
                "[document.querySelector('input[autocomplete=username]').value, document.querySelector('input[type=password]').value]"
            ) as? [String]
        XCTAssertEqual(filled, ["saved@example.com", "saved-secret"])

        _ = try await page.webView.evaluateJavaScript(
            "document.querySelector('input[type=password]').autocomplete = 'new-password'"
        )
        let generationRequest = try await focusPassword(in: page)
        try await page.fillGeneratedPassword("generated-secret", for: generationRequest.id)
        XCTAssertNil(page.credentialFillRequest)

        let revokedRequest = try await focusPassword(in: page)
        page.setCredentialAccessEnabled(false)
        XCTAssertNil(page.credentialFillRequest)
        do {
            try await page.fillGeneratedPassword("rejected-secret", for: revokedRequest.id)
            XCTFail("A revoked credential request must not fill the page")
        } catch {
            XCTAssertEqual(error as? BrowserCredentialFillError, .staleOrMismatchedRequest)
        }
        let password =
            try await page.webView.evaluateJavaScript(
                "document.querySelector('input[type=password]').value"
            ) as? String
        XCTAssertEqual(password, "generated-secret")
    }

    private func focusPassword(in page: BrowserPage) async throws -> BrowserCredentialFillRequest {
        let previousRequestID = page.credentialFillRequest?.id
        let focused = try await page.webView.callAsyncJavaScript(
            """
            const input = document.querySelector(selector);
            input.blur();
            input.focus();
            return document.activeElement === input;
            """,
            arguments: ["selector": "input[type=password]"],
            in: nil,
            contentWorld: .page
        )
        XCTAssertEqual(focused as? Bool, true)
        try await waitUntil {
            page.credentialFillRequest != nil && page.credentialFillRequest?.id != previousRequestID
        }
        return try XCTUnwrap(page.credentialFillRequest)
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

    private func makePage() throws -> BrowserPage {
        let tab = TabState.Seed.startPage()
        let space = SpaceState.Seed(
            name: "Routing",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
        let pool = BrowserPagePool(browser: .hostingPages(SessionState.Seed(spaces: [space])))
        pool.present(tab: tab.id, in: space.id)
        return try XCTUnwrap(pool.activePage)
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
}

/// Reports when a bare web view standing in for an adopted popup has finished
/// loading, so a test never races the document it is about to script.
@MainActor
private final class CredentialRoutingNavigationRecorder: NSObject, WKNavigationDelegate {
    private(set) var finishedNavigationCount = 0

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        finishedNavigationCount += 1
    }
}
