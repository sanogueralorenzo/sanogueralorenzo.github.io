import WebKit
import XCTest

@testable import Crest

/// The permission rules, their adoption from defaults, the lock gate and what
/// the device store keeps are core contracts (`SitePermissionLedgerTests` and
/// `SitePermissionStoreTests` in CrestCore). The platform makes the core's
/// `SiteOrigin` from URLs, WebKit frames and JSON answers itself, and every one
/// of those spellings must find the choices the core keeps for the origin.
@MainActor
final class BrowserSitePermissionCenterTests: XCTestCase {
    func testEverySpellingOfAnOriginIsOneOriginThatHashesAlike() throws {
        let origin = SiteOrigin(scheme: "https", host: "news.example", port: 443)
        let spellings = [
            SiteOrigin(scheme: "HTTPS", host: "News.Example", port: 0),
            SiteOrigin(scheme: "HTTPS", host: "News.Example", port: -1),
            try XCTUnwrap(SiteOrigin(url: try XCTUnwrap(URL(string: "https://News.Example/path")))),
            try JSONDecoder().decode(
                SiteOrigin.self, from: Data(#"{"scheme": "HTTPS", "host": "News.Example", "port": 0}"#.utf8)),
        ]
        for spelling in spellings {
            XCTAssertEqual(spelling, origin)
            XCTAssertEqual(spelling.hashValue, origin.hashValue)
        }
        XCTAssertEqual(Set(spellings), [origin])
        XCTAssertEqual(
            SiteOrigin(scheme: "HTTP", host: "News.Example", port: 0),
            SiteOrigin(scheme: "http", host: "news.example", port: 80))
        XCTAssertEqual(
            SiteOrigin(scheme: "Custom", host: "Handler.Example", port: 0),
            SiteOrigin(scheme: "custom", host: "handler.example", port: 0))
        XCTAssertEqual(SiteOrigin(scheme: "custom", host: "handler.example", port: 0).port, 0)
        XCTAssertNil(SiteOrigin(url: URL(fileURLWithPath: "/tmp/index.html")))
    }

    /// WebKit spells a URL's default port as 0. The origin WebKit gives a frame
    /// must still be the origin of the page's URL: the core's answers find the
    /// choice kept for it, and so must the platform's own comparisons, or
    /// revocation, the popup notice and prompt deduplication would each miss it.
    func testAWebKitFrameOriginMatchesTheChoiceKeptForItsPagesURL() async throws {
        let url = try XCTUnwrap(URL(string: "https://Camera.Crest.test/room"))
        let pageOrigin = try XCTUnwrap(SiteOrigin(url: url))
        let webKitOrigin = try await securityOrigin(ofPageAt: url)
        XCTAssertEqual(webKitOrigin.port, 0)
        let frameOrigin = SiteOrigin(webKitOrigin)
        let center = BrowserSitePermissionCenter()
        let changes = ChangeRecorder()
        center.addObserver(changes)
        let spaceID = UUID()

        center.setDecision(.denyPersistently, for: .camera, origin: pageOrigin, in: spaceID)

        XCTAssertEqual(frameOrigin, pageOrigin)
        XCTAssertEqual(center.decision(for: .camera, origin: frameOrigin, in: spaceID), .denyPersistently)
        XCTAssertTrue(changes.received.contains { $0.affects(.camera, origin: frameOrigin, in: spaceID) })
    }

    // MARK: - Support

    /// The security origin WebKit gives the main frame of a page loaded at `url`.
    private func securityOrigin(ofPageAt url: URL) async throws -> WKSecurityOrigin {
        let recorder = FrameOriginRecorder()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(recorder, name: FrameOriginRecorder.name)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        defer {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: FrameOriginRecorder.name)
        }
        webView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: "<script>webkit.messageHandlers.\(FrameOriginRecorder.name).postMessage(true)</script>")
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while recorder.origin == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        return try XCTUnwrap(recorder.origin, "The page never reported its frame.")
    }
}

/// Keeps every change the center tells its observers about.
@MainActor
private final class ChangeRecorder: BrowserSitePermissionObserver {
    // MARK: - Variables

    private(set) var received: [BrowserSitePermissionChange] = []

    // MARK: - Actions - Changes

    func sitePermissionsDidChange(_ change: BrowserSitePermissionChange) {
        received.append(change)
    }
}

/// Keeps the security origin of the frame that posts to it.
@MainActor
private final class FrameOriginRecorder: NSObject, WKScriptMessageHandler {
    // MARK: - Static Variables

    static let name = "frameOrigin"

    // MARK: - Variables

    private(set) var origin: WKSecurityOrigin?

    // MARK: - Actions - Messages

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        origin = message.frameInfo.securityOrigin
    }
}
