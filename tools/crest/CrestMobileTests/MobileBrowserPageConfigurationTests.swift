import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserPageConfigurationTests: XCTestCase {
    func testContextPreviewKeepsTheSourceProfileWithoutChangingItsPreferencesOrPage() throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let source = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        let url = try XCTUnwrap(URL(string: "https://preview.crest.test"))
        let preview = MobileBrowserLinkPreviewController(url: url, source: source, isCurrent: { true })

        XCTAssertTrue(preview.webView.configuration.websiteDataStore === source.configuration.websiteDataStore)
        XCTAssertFalse(preview.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(
            preview.webView.configuration.userContentController === source.configuration.userContentController)
        XCTAssertFalse(preview.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertTrue(source.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        XCTAssertNil(source.url)
    }
}
