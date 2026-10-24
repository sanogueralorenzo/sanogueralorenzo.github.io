import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserPageConfigurationTests: XCTestCase {
    func testMobilePageSuspendsInactiveWebContentLikeTheSharedFactory() throws {
        let space = makeSpace(index: 1)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let page = try openPage(in: space, through: browser)
        let configuration = page.webView.configuration

        XCTAssertEqual(
            configuration.preferences.inactiveSchedulingPolicy,
            .suspend,
            "iOS is the platform that jetsams, so resident background tabs must let WebKit suspend them."
        )
        XCTAssertTrue(configuration.preferences.isElementFullscreenEnabled)
        XCTAssertFalse(
            configuration.preferences.javaScriptCanOpenWindowsAutomatically,
            "Automatic popups require the owning site's permission."
        )
        XCTAssertFalse(configuration.limitsNavigationsToAppBoundDomains)
        XCTAssertTrue(configuration.upgradeKnownHostsToHTTPS)
        XCTAssertTrue(configuration.allowsAirPlayForMediaPlayback)
        XCTAssertFalse(configuration.suppressesIncrementalRendering)
    }

    func testMobilePageKeepsItsPlatformSpecificMediaAndPeekDecoration() throws {
        let space = makeSpace(index: 2)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let page = try openPage(in: space, through: browser)
        let configuration = page.webView.configuration

        XCTAssertEqual(
            configuration.defaultWebpagePreferences.preferredContentMode,
            .recommended,
            "Mobile keeps the recommended content mode rather than the shared desktop default."
        )
        XCTAssertTrue(configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertTrue(configuration.allowsInlineMediaPlayback)
        XCTAssertTrue(configuration.allowsPictureInPictureMediaPlayback)
        XCTAssertEqual(configuration.mediaTypesRequiringUserActionForPlayback, .all)
        XCTAssertTrue(
            configuration.userContentController.userScripts.contains {
                $0.source == MobileWebKit.inlineVideoScript.source
            }
        )
        XCTAssertTrue(
            page.hasActiveLinkActivationBridge,
            "Routing through the shared factory must keep the link-activation bridge installed."
        )
    }

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

    func testContextPreviewDoesNotLoadAfterItsSourceBecomesUnavailable() throws {
        let source = WKWebView(frame: .zero)
        let preview = MobileBrowserLinkPreviewController(
            url: try XCTUnwrap(URL(string: "https://preview.crest.test")), source: source, isCurrent: { false }
        )
        preview.loadViewIfNeeded()

        XCTAssertNil(preview.webView.url)
        XCTAssertFalse(preview.webView.isLoading)
    }

    func testMobileWebViewIsOnlyInspectableInADebugBuild() throws {
        let space = makeSpace(index: 3)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let page = try openPage(in: space, through: browser)

        #if DEBUG
            XCTAssertTrue(
                page.webView.isInspectable,
                "A debug build keeps Web Inspector available for development."
            )
        #else
            XCTAssertFalse(
                page.webView.isInspectable,
                "iOS ships no developer tooling, so a release web view must not accept an attached inspector."
            )
        #endif
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
