import Foundation
import Network
import UIKit
import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserInteropTests: XCTestCase {

    func testRealWebKitDownloadCompletesIntoTheAppDownloadsDirectory() async throws {
        let filename = "crest-mobile-\(UUID().uuidString).payload"
        let server = try MobileDownloadHTTPServer(payload: Data("real WebKit mobile download".utf8), filename: filename)
        let port = try await server.start()
        let sourceURL = try XCTUnwrap(URL(string: "http://localhost:\(port)/\(filename)"))
        let destination = URL.documentsDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(filename)
        let payload = Data("real WebKit mobile download".utf8)
        let profile = BrowsingProfile()
        let tab = TabState.Seed(
            title: "Download fixture",
            url: nil,
            symbol: "arrow.down.circle",
            placement: .current
        )
        let space = SpaceState.Seed(
            profileID: profile.id,
            name: "Download Space",
            symbol: "arrow.down.circle",
            accent: .teal,
            folders: [],
            tabs: [tab]
        )
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let downloads = MobileBrowserDownloads(core: browser.core, permissionCenter: BrowserSitePermissionCenter())
        let page = try XCTUnwrap(
            browser.openWebKitPage(in: space.id, for: tab.id).map { opened in
                MobileBrowserPage(
                    corePage: opened.core,
                    webKitPage: opened.webKit,
                    tab: browser.pageTab(tab.id, in: space.id),
                    space: browser.hostedSpace(space.id),
                    downloadCenter: downloads.center,
                    openNewTab: { _ in }
                )
            }
        )
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: destination)
        }

        page.webView.startDownload(using: URLRequest(url: sourceURL)) { download in
            page.webKitPage.startDownload(download, isUserInitiated: true)
        }

        let center = downloads.center
        try await waitUntil(timeout: 5) {
            center.items.first?.phase == .finished
                || center.items.contains { if case .failed = $0.phase { true } else { false } }
        }
        let item = try XCTUnwrap(center.items.first)
        XCTAssertEqual(item.profileID, profile.id)
        XCTAssertEqual(item.filename, filename)
        XCTAssertEqual(item.phase, .finished)
        XCTAssertEqual(item.destinationURL, destination)
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        await Self.removeDataStore(profile.id)
    }

    func testPrivateDisguisedExecutableDownloadWaitsForItsSpaceAndCancellationWritesNothing() async throws {
        let filename = "crest-private-\(UUID().uuidString).jpg"
        let server = try MobileDownloadHTTPServer(
            payload: Data("potentially dangerous private download".utf8),
            filename: filename,
            mimeType: "application/x-mach-binary"
        )
        let port = try await server.start()
        let sourceURL = try XCTUnwrap(URL(string: "http://localhost:\(port)/\(filename)"))
        let destination = URL.documentsDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(filename)
        let browser = BrowserStore.privateBrowsing(core: .hostingPages())
        let permissionCenter = BrowserSitePermissionCenter(core: browser.core)
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: .privateBrowsing,
            permissionCenter: permissionCenter
        )
        let privateSpace = try XCTUnwrap(browser.shownSpace)
        let sourceOrigin = try XCTUnwrap(SiteOrigin(url: sourceURL))
        permissionCenter.setDecision(
            .grantForSession,
            for: .automaticDownloads,
            origin: sourceOrigin,
            in: privateSpace.id
        )
        pages.select()
        let page = try XCTUnwrap(pages.activePage)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: destination)
            pages.downloadRiskConfirmation.cancelAll()
            pages.closePrivateBrowsingSession(browser.spaceModels.map(BrowserSpaceRuntimeAssignment.init(space:)))
        }

        // User initiation bypasses the extra prompt for ordinary installers.
        // An executable disguised as an image still requires confirmation.
        page.webView.startDownload(using: URLRequest(url: sourceURL)) { download in
            page.webKitPage.startDownload(download, isUserInitiated: true)
        }

        try await waitUntil(timeout: 5) {
            pages.downloadRiskConfirmation.request != nil
        }
        let request = try XCTUnwrap(pages.downloadRiskConfirmation.request)
        XCTAssertEqual(request.assessment.sanitizedFilename, filename)
        XCTAssertTrue(request.assessment.reasons.contains(.dangerousTypeMismatch))
        XCTAssertEqual(request.spaceName, "Private")
        XCTAssertEqual(request.sourceLabel, "localhost")
        XCTAssertEqual(pages.downloadCenter.items.first?.phase, .awaitingApproval)
        XCTAssertEqual(
            pages.downloadCenter.items.first?.profileID,
            privateSpace.profileID
        )

        pages.downloadRiskConfirmation.cancel()

        try await waitUntil(timeout: 5) {
            pages.downloadCenter.items.contains {
                if case .canceled = $0.phase { return true }
                return false
            }
        }
        XCTAssertEqual(pages.downloadCenter.items.first?.phase, .canceled)
        XCTAssertEqual(
            pages.downloadCenter.items.first?.message,
            "Canceled before downloading a potentially dangerous file."
        )
        XCTAssertNil(pages.downloadCenter.items.first?.destinationURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testADownloadFromAnotherSiteFollowsThePagesAutomaticDownloadChoice() async throws {
        let filename = "crest-cdn-\(UUID().uuidString).payload"
        let server = try MobileDownloadHTTPServer(
            payload: Data("download served by another site".utf8),
            filename: filename,
            pageHTML: "<!doctype html><title>Release</title>"
        )
        let port = try await server.start()
        let pageURL = try XCTUnwrap(URL(string: "http://localhost:\(port)/page"))
        // The file comes from another site, as a release page's files come
        // from its CDN.
        let fileURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/\(filename)"))
        let profile = BrowsingProfile()
        let tab = TabState.Seed(title: "Release", url: nil, placement: .current)
        let space = SpaceState.Seed(
            profileID: profile.id,
            name: "Download Space",
            symbol: "arrow.down.circle",
            accent: .teal,
            folders: [],
            tabs: [tab]
        )
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let permissionCenter = BrowserSitePermissionCenter(core: browser.core)
        let downloads = MobileBrowserDownloads(core: browser.core, permissionCenter: permissionCenter)
        let page = try XCTUnwrap(
            browser.openWebKitPage(in: space.id, for: tab.id).map { opened in
                MobileBrowserPage(
                    corePage: opened.core,
                    webKitPage: opened.webKit,
                    tab: browser.pageTab(tab.id, in: space.id),
                    space: browser.hostedSpace(space.id),
                    downloadCenter: downloads.center,
                    permissionCenter: permissionCenter,
                    openNewTab: { _ in }
                )
            }
        )
        permissionCenter.setDecision(
            .denyPersistently,
            for: .automaticDownloads,
            origin: try XCTUnwrap(SiteOrigin(url: pageURL)),
            in: space.id
        )
        defer { server.stop() }

        page.webView.load(URLRequest(url: pageURL))
        try await waitUntil(timeout: 5) {
            page.webView.backForwardList.currentItem?.url == pageURL && !page.webView.isLoading
        }
        // While this navigation becomes a download, the web view's URL is
        // already the file's; the page's site still owns the choice.
        page.webView.load(URLRequest(url: fileURL))

        // In the Simulator WebKit takes four to five seconds to hand a
        // navigation to another site over as a download.
        let center = downloads.center
        try await waitUntil(timeout: 15) {
            center.items.contains { $0.phase != .preparing }
        }
        XCTAssertEqual(center.items.first?.phase, .blockedAutomaticDownload)
        await Self.removeDataStore(profile.id)
    }

    func testADownloadsSignInIsAskedThroughItsPagesHostAndItsCredentialCompletesIt() async throws {
        let filename = "crest-auth-\(UUID().uuidString).payload"
        let server = try MobileDownloadHTTPServer(
            payload: Data("authenticated download".utf8),
            filename: filename,
            basicAuthentication: (username: "member", password: "test-secret")
        )
        let port = try await server.start()
        let sourceURL = try XCTUnwrap(URL(string: "http://localhost:\(port)/\(filename)"))
        let destination = URL.documentsDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(filename)
        let profile = BrowsingProfile()
        let tab = TabState.Seed(title: "Protected download", url: nil, placement: .current)
        let space = SpaceState.Seed(
            profileID: profile.id,
            name: "Download Space",
            symbol: "arrow.down.circle",
            accent: .teal,
            folders: [],
            tabs: [tab]
        )
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let downloads = MobileBrowserDownloads(core: browser.core, permissionCenter: BrowserSitePermissionCenter())
        let page = try XCTUnwrap(
            browser.openWebKitPage(in: space.id, for: tab.id).map { opened in
                MobileBrowserPage(
                    corePage: opened.core,
                    webKitPage: opened.webKit,
                    tab: browser.pageTab(tab.id, in: space.id),
                    space: browser.hostedSpace(space.id),
                    downloadCenter: downloads.center,
                    openNewTab: { _ in }
                )
            }
        )
        // The page's host answers the core's question with the member's sign-in.
        let host = SigningInPromptHost(core: browser.core)
        page.webKitPage.attach(host)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: destination)
        }

        page.webView.startDownload(using: URLRequest(url: sourceURL)) { download in
            page.webKitPage.startDownload(download, isUserInitiated: true)
        }

        let center = downloads.center
        try await waitUntil(timeout: 5) {
            center.items.first?.phase == .finished
                || center.items.contains { if case .failed = $0.phase { true } else { false } }
        }

        XCTAssertEqual(center.items.first?.phase, .finished)
        XCTAssertEqual(host.asked.map(\.question.host), ["localhost"])
        XCTAssertEqual(try Data(contentsOf: destination), Data("authenticated download".utf8))
        await Self.removeDataStore(profile.id)
    }

    func testDisplayableInlineDirectVideoUsesMobilePlaybackDocument() throws {
        let url = try XCTUnwrap(
            URL(string: "https://media.example/watch?id=mobile&quality=source")
        )
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 206,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "video/mp4",
                    "Content-Disposition": "inline",
                ]
            )
        )

        let navigation = try XCTUnwrap(
            BrowserDirectMediaNavigation.classify(
                canShowMIMEType: true,
                isForMainFrame: true,
                response: response
            )
        )

        XCTAssertEqual(navigation.url, url)
        XCTAssertEqual(navigation.kind, .video)
        XCTAssertTrue(navigation.responseHTML.contains("playsinline"))
        XCTAssertTrue(
            navigation.responseHTML.contains(
                "https://media.example/watch?id=mobile&amp;quality=source"
            )
        )
    }

    func testMobileDownloadTransferMovesFromPrivateStagingToTheVisibleRecord() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = root.appendingPathComponent("Staging/source.txt")
        let destination = root.appendingPathComponent("Downloads/report.txt")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(
            at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("mobile download".utf8).write(to: staging)

        try BrowserDownloadTransfer.finish(from: staging, to: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(try Data(contentsOf: destination), Data("mobile download".utf8))
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while try await !condition() {
            if Date() >= deadline {
                throw MobileBrowserInteropTestError.timedOutWaitingForDownload
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func removeDataStore(_ identifier: UUID) async {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in continuation.resume() }
        }
    }

    func testAutomaticPopupBridgeBlocksCoalescesAndAllowsOnlyANewAttempt() async throws {
        let context = try makePopupContext()
        let origin = try XCTUnwrap(URL(string: "https://mobile-popups.crest.test/"))
        let siteOrigin = try XCTUnwrap(SiteOrigin(url: origin))
        context.opener.webView.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        context.opener.webView.loadSimulatedRequest(
            URLRequest(url: origin),
            responseHTML: """
                <!doctype html><html><body><script>
                globalThis.results = [];
                globalThis.tryPopup = () => {
                  const result = window.open('about:blank') === null ? 'null' : 'window';
                  globalThis.results.push(result);
                  return result;
                };
                setTimeout(() => {
                  globalThis.tryPopup();
                  globalThis.tryPopup();
                  globalThis.tryPopup();
                }, 100);
                </script></body></html>
                """
        )

        // Observe the fixture's attempts before checking the native notice.
        // A native-only poll leaves this unmounted page's timers suspended.
        try await waitUntil(timeout: 5) {
            (try? await context.opener.webView.evaluateJavaScript("globalThis.results?.length")) as? Int == 3
        }
        try await waitUntil(timeout: 5) {
            context.opener.blockedPopupState.notice?.status == .blocked
        }
        let blockedResults =
            try await context.opener.webView.callAsyncJavaScript(
                "return globalThis.results.join(',');",
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? String
        XCTAssertEqual(blockedResults, "null,null,null")
        XCTAssertEqual(context.store.shownSpace?.tabs.models.count, 1)
        XCTAssertEqual(context.opener.blockedPopupState.indicationRevision, 1)

        context.opener.allowAutomaticPopupsForBlockedSite()

        XCTAssertEqual(
            context.pages.permissionCenter.decision(
                for: .popups,
                origin: siteOrigin,
                in: context.opener.spaceID
            ),
            .grantPersistently
        )
        XCTAssertEqual(
            context.opener.blockedPopupState.notice?.status,
            .allowedAwaitingRetry
        )
        XCTAssertEqual(context.store.shownSpace?.tabs.models.count, 1)

        let retryResult =
            try await context.opener.webView.callAsyncJavaScript(
                "return globalThis.tryPopup();",
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? String
        XCTAssertEqual(retryResult, "window")
        try await waitUntil(timeout: 5) {
            context.store.shownSpace?.tabs.models.count == 2
        }
        XCTAssertNil(context.opener.blockedPopupState.notice)
        XCTAssertTrue(context.pages.activePage?.wasOpenedAsPopup == true)

        context.pages.reconcile(validTabIDs: [])
    }

    func testAdoptedPopupWebViewIsTheOneRegisteredForItsPopupTab() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()

        let popupWebView = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        let popupPage = try XCTUnwrap(context.pages.activePage)
        XCTAssertTrue(popupPage.webView === popupWebView)
        XCTAssertTrue(popupPage.wasOpenedAsPopup)
        XCTAssertTrue(popupPage.isAwaitingPopupNavigation)
        XCTAssertNil(popupPage.live.pendingNavigationURL)
        XCTAssertFalse(context.opener.wasOpenedAsPopup)
    }

    func testAdoptedPopupInheritsTheOpenerWebsiteDataStoreAndProfile() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let context = try makePopupContext()

        let popupWebView = try XCTUnwrap(
            context.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        let popupPage = try XCTUnwrap(context.pages.activePage)
        XCTAssertTrue(
            popupWebView.configuration.websiteDataStore
                === context.opener.webView.configuration.websiteDataStore
        )
        XCTAssertEqual(popupPage.spaceID, context.opener.spaceID)
        XCTAssertEqual(popupPage.profileID, context.opener.profileID)
    }

    func testClosingAPageTheUserOpenedKeepsItsTab() throws {
        let context = try makePopupContext()
        let openerTabID = try XCTUnwrap(context.store.shownTab?.id)

        context.opener.webViewDidClose(context.opener.webView)

        XCTAssertEqual(context.store.shownTab?.id, openerTabID)
        XCTAssertTrue(
            context.store.shownSpace?.tabs.contains(openerTabID) == true
        )
    }

    func testPrivatePopupAdoptionStaysInsideThePrivateStore() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let regular = try makePopupContext()
        let privateContext = try makePopupContext(browsingMode: .privateBrowsing)

        let popupWebView = try XCTUnwrap(
            privateContext.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        XCTAssertFalse(popupWebView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(privateContext.store.shownSpace?.tabs.models.count, 2)
        XCTAssertEqual(regular.store.shownSpace?.tabs.models.count, 1)
        XCTAssertTrue(privateContext.pages.activePage?.wasOpenedAsPopup == true)
        XCTAssertFalse(regular.pages.activePage?.wasOpenedAsPopup == true)
    }

    func testBlockedPopupStateDoesNotLeakIntoAPrivateSession() throws {
        let regular = try makePopupContext()
        let privateContext = try makePopupContext(browsingMode: .privateBrowsing)
        let origin = SiteOrigin(
            scheme: "https",
            host: "private-popups.example",
            port: 443
        )
        var regularState = regular.opener.blockedPopupState
        XCTAssertTrue(
            regularState.recordBlockedAttempt(
                documentIdentifier: "regular-document",
                origin: origin
            )
        )
        regular.opener.blockedPopupState = regularState

        XCTAssertNotNil(regular.opener.blockedPopupState.notice)
        XCTAssertNil(privateContext.opener.blockedPopupState.notice)
        XCTAssertEqual(
            privateContext.pages.permissionCenter.decision(
                for: .popups,
                origin: origin,
                in: privateContext.opener.spaceID
            ),
            .ask
        )
    }

    // MARK: - Archived tab state

    // MARK: - Idle unloading

    // MARK: - Relocking a protected Space

    func testRelockingAProtectedSpacePreservesItsResidentPageAndOtherPresentation() throws {
        let secret = TabState.Seed(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeStateSpace(
            tabs: [secret],
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = TabState.Seed(title: "Open", url: nil, placement: .current)
        let openSpace = makeStateSpace(tabs: [openTab])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [protectedSpace, openSpace]), showing: openSpace.id,
            tabs: [openSpace.id: openTab.id, protectedSpace.id: secret.id])
        browser.unlockForTesting(protectedSpace)
        let pages = MobileBrowserPageStore(browser: browser)
        let protectedModel = try XCTUnwrap(browser.spaceModel(protectedSpace.id))

        pages.select()
        pages.present(tab: secret.id, in: protectedSpace.id)
        let secretPage = try XCTUnwrap(pages.activePage)
        XCTAssertTrue(pages.containsResidentPage(for: secret.id))

        pages.relockProtectedSpace(protectedModel)

        XCTAssertNil(pages.activePage)
        XCTAssertTrue(pages.presentedTabIDs.isEmpty)
        XCTAssertTrue(pages.containsResidentPage(for: secret.id))
        XCTAssertTrue(pages.containsResidentPage(for: openTab.id))

        pages.select()
        XCTAssertTrue(pages.activePage === secretPage)
        pages.present(tab: openTab.id, in: openSpace.id)
        let openPage = pages.activePage
        pages.relockProtectedSpace(protectedModel)
        XCTAssertTrue(pages.activePage === openPage)
        XCTAssertEqual(pages.presentedTabIDs, [openTab.id])
    }

    private func makeStateSpace(
        id: UUID = UUID(),
        profileID: UUID = UUID(),
        tabs: [TabState.Seed],
        accessPolicy: SpaceAccessPolicy = .open
    ) -> SpaceState.Seed {
        SpaceState.Seed(
            id: id,
            profileID: profileID,
            name: "State",
            symbol: "clock.arrow.circlepath",
            accent: .teal,
            folders: [],
            tabs: tabs,
            accessPolicy: accessPolicy
        )
    }

    private func makePopupContext(
        browsingMode: BrowserBrowsingMode = .standard,
        tabStateArchive: (any BrowserTabStateArchiving)? = nil
    ) throws -> MobilePopupAdoptionContext {
        let space = makePopupSpace()
        let store = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]),
            showing: space.id,
            tabs: [space.id: try XCTUnwrap(space.tabs.first?.id)]
        )
        let pages = MobileBrowserPageStore(
            browser: store,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: tabStateArchive == nil,
            tabStateArchive: tabStateArchive
        )
        pages.select()
        return MobilePopupAdoptionContext(
            store: store,
            pages: pages,
            opener: try XCTUnwrap(pages.activePage)
        )
    }

    /// A start-page opener keeps the fixture offline: a resident page loads its
    /// tab's URL as soon as it is built.
    private func makePopupSpace() -> SpaceState.Seed {
        let openerTab = TabState.Seed(title: "Opener", url: nil, placement: .current)
        return SpaceState.Seed(
            name: "Popups",
            symbol: "macwindow.on.rectangle",
            accent: .teal,
            folders: [],
            tabs: [openerTab]
        )
    }
}

/// One opener page, its store, and the store that owns their tabs, so popup tests
/// drive the real `WKUIDelegate` entry point instead of the adoption API.
@MainActor
private struct MobilePopupAdoptionContext {
    let store: BrowserStore
    let pages: MobileBrowserPageStore
    let opener: MobileBrowserPage

    /// Hands the opener a configuration copied from its own, which is what WebKit
    /// does before calling `createWebViewWith`.
    func requestPopup(url: URL?, navigationType: WKNavigationType) -> WKWebView? {
        guard
            let configuration = opener.webView.configuration
                .copy() as? WKWebViewConfiguration
        else { return nil }
        return opener.webView(
            opener.webView,
            createWebViewWith: configuration,
            for: StubPopupNavigationAction(url: url, navigationType: navigationType),
            windowFeatures: WKWindowFeatures()
        )
    }
}

/// WebKit never lets an app build a real `WKNavigationAction`, so popup tests
/// stand in for the one WebKit hands to `createWebViewWith`: no target frame and
/// a navigation type that selects the popup trigger under test.
private final class StubPopupNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
    private let stubRequest: URLRequest
    private let stubNavigationType: WKNavigationType
    private let stubModifierFlags: UIKeyModifierFlags
    private let stubButtonNumber: UIEvent.ButtonMask

    init(
        url: URL?, navigationType: WKNavigationType, modifierFlags: UIKeyModifierFlags = [],
        buttonNumber: UIEvent.ButtonMask = []
    ) {
        // `window.open()` without a destination reaches WebKit as a request
        // without a URL, which a stub can only reproduce by clearing it.
        var request = URLRequest(url: URL(fileURLWithPath: "/"))
        request.url = url
        stubRequest = request
        stubNavigationType = navigationType
        stubModifierFlags = modifierFlags
        stubButtonNumber = buttonNumber
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { stubNavigationType }
    override var targetFrame: WKFrameInfo? { nil }
    override var modifierFlags: UIKeyModifierFlags { stubModifierFlags }
    override var buttonNumber: UIEvent.ButtonMask { stubButtonNumber }
    var browserSourceOrigin: SiteOrigin? { nil }
}

private enum MobileBrowserInteropTestError: Error {
    case timedOutWaitingForDownload
    case listenerFailed
}

private final class MobileDownloadHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.pauldavis.crest.tests.mobile-download")
    private let responseData: Data
    private let unauthorizedResponseData: Data
    private let requiredAuthorizationHeader: String?
    /// The page `GET /page` answers with, when the server has one.
    private let pageResponseData: Data?

    init(
        payload: Data,
        filename: String,
        mimeType: String = "application/octet-stream",
        basicAuthentication: (username: String, password: String)? = nil,
        pageHTML: String? = nil
    ) throws {
        listener = try NWListener(using: .tcp, on: .any)
        pageResponseData = pageHTML.map { html in
            Data(
                """
                HTTP/1.1 200 OK\r
                Content-Type: text/html\r
                Content-Length: \(html.utf8.count)\r
                Connection: close\r
                \r
                \(html)
                """.utf8
            )
        }
        let header = """
            HTTP/1.1 200 OK\r
            Content-Type: \(mimeType)\r
            Content-Disposition: attachment; filename="\(filename)"\r
            Content-Length: \(payload.count)\r
            Connection: close\r
            \r

            """
        responseData = Data(header.utf8) + payload
        unauthorizedResponseData = Data(
            """
            HTTP/1.1 401 Unauthorized\r
            WWW-Authenticate: Basic realm="Crest Tests"\r
            Content-Length: 0\r
            Connection: close\r
            \r

            """.utf8
        )
        requiredAuthorizationHeader = basicAuthentication.map {
            let encoded = Data("\($0.username):\($0.password)".utf8).base64EncodedString()
            return "authorization: basic \(encoded)".lowercased()
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: MobileBrowserInteropTestError.listenerFailed)
                        return
                    }
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: port.rawValue)
                case .failed:
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: MobileBrowserInteropTestError.listenerFailed)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard state == .ready, let self, let connection else { return }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) {
                [weak self, weak connection] data, _, _, error in
                guard let self, let connection, data != nil, error == nil else {
                    connection?.cancel()
                    return
                }
                let request = data.flatMap { String(data: $0, encoding: .utf8) }?.lowercased()
                let response =
                    if let pageResponseData, request?.hasPrefix("get /page ") == true {
                        pageResponseData
                    } else {
                        requiredAuthorizationHeader.map {
                            request?.contains($0) == true ? responseData : unauthorizedResponseData
                        } ?? responseData
                    }
                connection.send(
                    content: response,
                    contentContext: .defaultMessage,
                    isComplete: true,
                    completion: .contentProcessed { _ in connection.cancel() }
                )
            }
        }
        connection.start(queue: queue)
    }
}

/// A page's host that answers a server's sign-in question through the core
/// with one member's credential, and remembers what it was asked.
@MainActor
private final class SigningInPromptHost: WebKitPageHosting {
    private let core: CrestCore
    private(set) var asked: [AuthenticationAsked] = []

    init(core: CrestCore) {
        self.core = core
    }

    func ask(_ asked: ScriptDialogAsked, dismissal: BrowserPromptDismissal) {
        _ = try? core.send(AnswerScriptDialog(promptID: asked.promptID, accepted: false, text: nil))
    }

    func ask(_ asked: AuthenticationAsked, dismissal: BrowserPromptDismissal) {
        self.asked.append(asked)
        _ = try? core.send(
            AnswerAuthentication(
                promptID: asked.promptID,
                credential: AuthenticationCredential(username: "member", password: "test-secret")))
    }

    func ask(_ asked: PermissionAsked, dismissal: BrowserPromptDismissal) {
        _ = try? core.send(AnswerPermission(promptID: asked.promptID, grants: false, remembers: false))
    }

    func prepareToLoad(_ url: URL) {}

    func mediaActivityMayHaveChanged() {}

    func historyMayHaveChanged() {}
}
