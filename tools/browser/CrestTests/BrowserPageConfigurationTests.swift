import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageConfigurationTests: XCTestCase {
    func testProductionConfigurationUsesTheSpacesPersistentStoreAndDesktopBrowserDefaults() {
        let profile = BrowsingProfile()

        let configuration = BrowserPageConfiguration.make(
            for: profile,
            websiteDataStore: BrowserWebsiteDataStore.persistent(for: profile)
        )

        XCTAssertEqual(configuration.websiteDataStore.identifier, profile.id)
        XCTAssertEqual(
            configuration.applicationNameForUserAgent,
            BrowserPlatformUserAgent.applicationName
        )
        XCTAssertEqual(configuration.defaultWebpagePreferences.preferredContentMode, .desktop)
        XCTAssertTrue(configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertTrue(configuration.allowsAirPlayForMediaPlayback)
        XCTAssertTrue(configuration.preferences.isElementFullscreenEnabled)
        XCTAssertFalse(
            configuration.preferences.javaScriptCanOpenWindowsAutomatically,
            "Automatic windows are blocked until the site has explicit permission; user-activated windows are unaffected by this WebKit setting."
        )
        XCTAssertEqual(configuration.preferences.inactiveSchedulingPolicy, .suspend)
        XCTAssertTrue(configuration.upgradeKnownHostsToHTTPS)
        XCTAssertFalse(configuration.suppressesIncrementalRendering)
        XCTAssertFalse(configuration.limitsNavigationsToAppBoundDomains)
    }

    func testTheFactoryHonoursARequestedContentModeAndPlatformDecoration() {
        let profile = BrowsingProfile()
        var decoratedConfigurations = 0

        let configuration = BrowserPageConfiguration.make(
            for: profile,
            websiteDataStore: WKWebsiteDataStore.nonPersistent(),
            preferredContentMode: .recommended
        ) { configuration in
            decoratedConfigurations += 1
            configuration.suppressesIncrementalRendering = true
        }

        XCTAssertEqual(decoratedConfigurations, 1)
        XCTAssertEqual(
            configuration.defaultWebpagePreferences.preferredContentMode,
            .recommended
        )
        XCTAssertTrue(
            configuration.suppressesIncrementalRendering,
            "A platform decoration runs last so it can override a shared default."
        )
        XCTAssertEqual(
            configuration.preferences.inactiveSchedulingPolicy,
            .suspend,
            "Every platform gets the shared WebKit settings the factory owns."
        )
        XCTAssertTrue(configuration.preferences.isElementFullscreenEnabled)
    }

    func testProductionWebViewAdvertisesDesktopSafariCompatibility() async throws {
        let profile = BrowsingProfile()
        let applicationName = try XCTUnwrap(BrowserPlatformUserAgent.applicationName)
        let webView = WKWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(for: profile)
        )

        let userAgent = try await webView.evaluateJavaScript("navigator.userAgent") as? String

        XCTAssertEqual(
            userAgent?.hasSuffix(applicationName),
            true
        )
        XCTAssertFalse(userAgent?.contains("Crest/") == true)
    }

    func testDesktopWebViewAcceptsTheClickThatActivatesItsWindow() {
        let webView = BrowserDesktopWebView(
            frame: .zero,
            configuration: BrowserPageConfiguration.make(for: BrowsingProfile())
        )

        XCTAssertTrue(webView.acceptsFirstMouse(for: nil))
    }

    func testPrivateConfigurationUsesTheSuppliedNonPersistentStore() {
        let profile = BrowsingProfile()
        let dataStore = WKWebsiteDataStore.nonPersistent()

        let configuration = BrowserPageConfiguration.make(
            for: profile,
            websiteDataStore: dataStore
        )

        XCTAssertTrue(configuration.websiteDataStore === dataStore)
        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertNil(configuration.websiteDataStore.identifier)
    }
}
