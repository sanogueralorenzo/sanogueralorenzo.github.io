import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserCredentialTests: XCTestCase {
    func testMobilePageInstallsTheSharedCredentialBridgeInEveryFrame() throws {
        let space = makeSpace(index: 1)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let page = try openPage(in: space, through: browser)
        let scripts = page.webView.configuration.userContentController.userScripts

        XCTAssertTrue(
            scripts.contains {
                $0.source == BrowserCredentialContentBridge.source
                    && $0.injectionTime == .atDocumentStart
                    && !$0.isForMainFrameOnly
            })
    }

    func testMobilePageReceivesASuccessfulIsolatedWorldFormSubmission() async throws {
        let space = makeSpace(index: 7)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let page = try openPage(in: space, through: browser)
        let request = URLRequest(url: URL(string: "https://forms.crest.test/login")!)
        page.webView.loadSimulatedRequest(
            request,
            responseHTML: """
                <!doctype html>
                <style>input { display: block; width: 220px; height: 32px; }</style>
                <form id="mobile-login">
                  <input autocomplete="username" value="mobile@example.com">
                  <input type="password" autocomplete="current-password" value="mobile-secret">
                  <button type="button">Sign In</button>
                </form>
                """)
        try await waitUntil { page.completedNavigationCount == 1 }

        let didCapture = try await page.webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.captureForTesting(selector) === true;",
            arguments: ["selector": "#mobile-login"],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        XCTAssertEqual(didCapture as? Bool, true)
        XCTAssertNil(page.credentialSaveCandidate)

        _ = try await page.webView.callAsyncJavaScript(
            "document.querySelector('#mobile-login').remove(); return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil { page.credentialSaveCandidate != nil }

        let candidate = try XCTUnwrap(page.credentialSaveCandidate)
        XCTAssertEqual(candidate.username, "mobile@example.com")
        XCTAssertEqual(candidate.password, "mobile-secret")
        XCTAssertEqual(candidate.origin, try origin("https://forms.crest.test/login"))
        XCTAssertFalse(candidate.description.contains("mobile-secret"))
        page.dismissCredentialSaveCandidate()
    }

    private func origin(_ value: String) throws -> CredentialOrigin {
        try XCTUnwrap(CredentialOrigin(url: try XCTUnwrap(URL(string: value))))
    }

    /// Opens the page for `space`'s first tab through `browser`'s core, as a
    /// page store opens one. Keep `browser` alive while the page is in use.
    private func openPage(in space: SpaceState.Seed, through browser: BrowserStore) throws -> MobileBrowserPage {
        let tab = try XCTUnwrap(space.tabs.first)
        return try XCTUnwrap(
            browser.openWebKitPage(in: space.id, for: tab.id).map { opened in
                MobileBrowserPage(
                    corePage: opened.core, webKitPage: opened.webKit, tab: browser.pageTab(tab.id, in: space.id),
                    space: browser.hostedSpace(space.id), openNewTab: { _ in })
            }
        )
    }

    private func makeSpace(index: Int) -> SpaceState.Seed {
        let tab = TabState.Seed(
            id: fixedUUID(index * 10 + 1),
            title: "New Tab",
            url: nil,
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

    private func waitUntil(
        timeout: Duration = .seconds(8),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the mobile WebKit credential state")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
