import SwiftUI
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserWebCompatibilityTests: XCTestCase {

    func testLocalStorageAndIndexedDBRemainInsideOneSpaceProfile() async throws {
        let profileA = BrowsingProfile()
        let profileB = BrowsingProfile()
        let origin = URL(string: "https://storage.crest.test/")!
        let dataStoreA = BrowserWebsiteDataStore.persistent(for: profileA)
        let dataStoreB = BrowserWebsiteDataStore.persistent(for: profileB)

        do {
            let pageA = WKWebView(
                frame: .zero,
                configuration: BrowserPageConfiguration.make(
                    for: profileA,
                    websiteDataStore: dataStoreA
                )
            )
            let pageB = WKWebView(
                frame: .zero,
                configuration: BrowserPageConfiguration.make(
                    for: profileB,
                    websiteDataStore: dataStoreB
                )
            )
            try await loadFixture(on: pageA, origin: origin)
            try await loadFixture(on: pageB, origin: origin)

            let storedValue = try await stringResult(
                from: pageA,
                script: "localStorage.setItem('space-token', 'space-a'); return localStorage.getItem('space-token');"
            )
            let indexedDBValue = try await stringResult(from: pageA, script: indexedDBRoundTripScript)
            let cacheStorageValue = try await stringResult(from: pageA, script: cacheStorageWriteScript)
            let otherSpaceValue = try await nullableStringResult(
                from: pageB,
                script: "return localStorage.getItem('space-token');"
            )
            let otherSpaceCache = try await nullableStringResult(
                from: pageB,
                script: cacheStorageReadScript
            )

            XCTAssertEqual(storedValue, "space-a")
            XCTAssertEqual(indexedDBValue, "indexed-db-ready")
            XCTAssertEqual(cacheStorageValue, "cache-ready")
            XCTAssertNil(otherSpaceValue)
            XCTAssertNil(otherSpaceCache)

            let rehydratedA = WKWebView(
                frame: .zero,
                configuration: BrowserPageConfiguration.make(
                    for: profileA,
                    websiteDataStore: BrowserWebsiteDataStore.persistent(
                        for: profileA
                    )
                )
            )
            try await loadFixture(on: rehydratedA, origin: origin)
            let rehydratedValue = try await stringResult(
                from: rehydratedA,
                script: "return localStorage.getItem('space-token');"
            )
            let rehydratedCache = try await nullableStringResult(
                from: rehydratedA,
                script: cacheStorageReadScript
            )
            XCTAssertEqual(rehydratedValue, "space-a")
            XCTAssertEqual(rehydratedCache, "cache-ready")
        }

        await removeDataStore(profileA.id)
        await removeDataStore(profileB.id)
    }

    func testUnapprovedAutomaticWindowOpenIsBlockedAndCoalesced() async throws {
        let origin = try XCTUnwrap(URL(string: "https://blocked-popups.crest.test/"))
        let openerTab = TabState.Seed(title: "Opener", url: nil, placement: .current)
        let profile = BrowsingProfile()
        let space = makeSpace(profile: profile, tabs: [openerTab])
        let store = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space])
        )
        let pool = BrowserPagePool(browser: store)

        do {
            pool.select()
            let opener = try XCTUnwrap(pool.activePage)
            opener.webView.loadSimulatedRequest(
                URLRequest(url: origin),
                responseHTML: try blockedPopupFixtureHTML()
            )
            try await waitUntil("the popup blocker fixture to load") {
                opener.live.documentURL == origin && !opener.live.isLoading
            }

            XCTAssertFalse(
                opener.webView.configuration.preferences
                    .javaScriptCanOpenWindowsAutomatically
            )
            try await waitUntil("all automatic window requests to run") {
                try await self.intResult(
                    from: opener.webView,
                    script: "return globalThis.automaticPopupResults.length;"
                ) == 3
            }
            let openResults = try await stringResult(
                from: opener.webView,
                script: "return globalThis.automaticPopupResults.join(',');"
            )

            XCTAssertEqual(openResults, "null,null,null")
            XCTAssertEqual(store.shownSpace?.tabs.models.map(\.id), [openerTab.id])
            XCTAssertEqual(
                opener.blockedPopupState.notice,
                BrowserBlockedPopupNotice(
                    origin: try XCTUnwrap(SiteOrigin(url: origin)),
                    status: .blocked
                )
            )
            XCTAssertEqual(opener.blockedPopupState.indicationRevision, 1)

            let navigatedOrigin = try XCTUnwrap(
                URL(string: "https://after-blocked-popup.crest.test/?automatic=0")
            )
            opener.webView.loadSimulatedRequest(
                URLRequest(url: navigatedOrigin),
                responseHTML: try blockedPopupFixtureHTML()
            )
            try await waitUntil("navigation away from the blocked document") {
                opener.live.documentURL == navigatedOrigin && !opener.live.isLoading
            }
            XCTAssertNil(
                opener.blockedPopupState.notice,
                "A blocked indication cannot survive top-level navigation."
            )
        }

        await removeDataStore(profile.id)
    }

    /// The shape of a Google Identity Services sign-in, in a window that was
    /// closed and opened again under the same identity, as the first window
    /// is, while the pool of the window that closed is still alive: a
    /// cross-site frame in the page opens a sized popup, which redirects
    /// across sites to a page the person must use, then posts back to the
    /// frame that opened it and closes itself. The popup is one Quick Window
    /// over the window the person is using, which keeps its opener, and no
    /// tab appears.
    func testASignInPopupFromACrossSiteFrameShowsInOneQuickWindowThatKeepsItsOpenerAndClosesItself() async throws {
        let server = try BrowserPrivacyHTTPServer()
        try await server.start()
        defer { server.stop() }
        let port = server.port
        let (site, provider) = ("127.0.0.1", "localhost")
        server.overrideResponse = { request in
            func page(_ body: String) -> (status: String, headers: String, body: Data) {
                ("200 OK", "Content-Type: text/html\r\n", Data("<!doctype html><html><body>\(body)</body></html>".utf8))
            }
            func redirect(_ location: String) -> (status: String, headers: String, body: Data) {
                ("302 Found", "Location: \(location)\r\n", Data())
            }
            switch request.path {
            case "/opener":
                return page(
                    """
                    <iframe src="http://\(provider):\(port)/button"></iframe>
                    <script>
                    addEventListener('message', event => { globalThis.fromFrame = String(event.data); });
                    </script>
                    """)
            case "/button":
                return page(
                    """
                    <script>
                    addEventListener('message', event => {
                      if (event.data === 'open') {
                        const popup = window.open('http://\(provider):\(port)/select', 'crest_sign_in',
                          'width=500,height=600');
                        parent.postMessage(popup === null ? 'null' : 'window', '*');
                      } else if (event.source !== parent) {
                        parent.postMessage('relayed:' + event.data, '*');
                      }
                    });
                    parent.postMessage('ready', '*');
                    </script>
                    """)
            case "/select": return redirect("http://\(site):\(port)/bounce")
            case "/bounce": return redirect("http://\(provider):\(port)/consent")
            case "/consent":
                return page(
                    """
                    <button id="continue" onclick="location.href = '/done'">Continue</button>
                    """)
            case "/done":
                return page(
                    """
                    <script>
                    if (window.opener) { window.opener.postMessage('signed-in', '*'); }
                    setTimeout(() => window.close(), 100);
                    </script>
                    """)
            default: return ("404 Not Found", "", Data())
            }
        }

        let openerTab = TabState.Seed(title: "Opener", url: nil, placement: .current)
        let profile = BrowsingProfile()
        let space = makeSpace(profile: profile, tabs: [openerTab])
        let store = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let primary = BrowserPagePool(browser: store)
        let spaceAccess = BrowserSpaceAccessController(authenticator: BrowserPreviewAuthenticator(result: true))
        let windowID = UUID()
        func openWindow() -> (browser: BrowserStore, pages: BrowserPagePool) {
            let browser = store.makeWindowStore(
                BrowserWindowOpening(id: windowID, saved: true, copying: store.windowID))
            let pages = primary.makeWindowPool(
                browser: browser, sharesRuntimes: true, transientBrowsing: BrowserTransientBrowsingCoordinator(),
                spaceAccess: spaceAccess)
            return (browser, pages)
        }
        let quickWindows = QuickWindowStandIn(browser: store, primary: primary, spaceAccess: spaceAccess)
        // The window closed, but its pool, whose view had installed a way to
        // open Quick Windows, is still alive when the window opens again.
        let closed = openWindow()
        closed.pages.popupWindowPresenter = { quickWindows.open($0) }
        closed.pages.releaseWindowPresentation()
        closed.browser.close()
        let window = openWindow()
        window.pages.popupWindowPresenter = { quickWindows.open($0) }
        quickWindows.registry.register(window.pages, browser: window.browser, for: windowID)

        do {
            window.pages.select()
            let opener = try XCTUnwrap(window.pages.activePage)
            let origin = server.url(host: site, path: "/opener")
            // The frame asks for its window from a message, as a sign-in
            // library does from its own events, so the site allows windows.
            window.pages.permissionCenter.setDecision(
                .grantPersistently, for: .popups, origin: try XCTUnwrap(SiteOrigin(url: origin)), in: space.id)
            opener.synchronizePopupPermission(for: origin)
            opener.load(origin)
            try await waitUntil("the sign-in frame to load") {
                try await self.stringResult(from: opener.webView, script: "return globalThis.fromFrame ?? '';")
                    == "ready"
            }

            _ = try await stringResult(
                from: opener.webView,
                script: "document.querySelector('iframe').contentWindow.postMessage('open', '*'); return 'sent';")
            try await waitUntil("window.open() to hand the frame a window") {
                try await self.stringResult(from: opener.webView, script: "return globalThis.fromFrame ?? '';")
                    == "window"
            }

            // The popup shows in one Quick Window, across both redirects.
            let consent = server.url(host: provider, path: "/consent")
            try await waitUntil("the Quick Window to show the provider's page", timeout: .seconds(15)) {
                quickWindows.models.first?.page?.live.documentURL == consent
            }
            XCTAssertEqual(quickWindows.requests.count, 1, "A sign-in popup opens one Quick Window.")
            let quickWindow = try XCTUnwrap(quickWindows.models.first)
            let popup = try XCTUnwrap(quickWindow.page)
            XCTAssertTrue(popup.wasOpenedAsPopup)
            // The person sees it: the popup's page is in the Quick Window, on screen.
            let shown = try XCTUnwrap(quickWindows.windows.first)
            try await waitUntil("the Quick Window to show the popup on screen") {
                popup.webView.window === shown && shown.isVisible && popup.webView.bounds.width > 0
            }
            // The address changes when the consent page commits, before its
            // body is parsed, so the button is waited for rather than assumed.
            try await waitUntil("the consent page's button to load") {
                try await self.stringResult(
                    from: popup.webView, script: "return document.querySelector('#continue') ? 'ready' : '';")
                    == "ready"
            }
            _ = try await stringResult(
                from: popup.webView, script: "document.querySelector('#continue').click(); return 'clicked';")

            try await waitUntil("the popup to report back through its opener") {
                try await self.stringResult(from: opener.webView, script: "return globalThis.fromFrame ?? '';")
                    == "relayed:signed-in"
            }
            try await waitUntil("window.close() to close the Quick Window") { quickWindow.wasClosedByPage }
            XCTAssertEqual(store.shownSpace?.tabs.models.map(\.id), [openerTab.id])
        }
        quickWindows.closeAll()

        await removeDataStore(profile.id)
    }

    /// Stands in for the process host's Quick Windows, as the Chromium build
    /// opens them: a window over the Quick Window's own view, for the context
    /// its target window resolves to through the pool registry, opened while
    /// the page waits.
    @MainActor
    private final class QuickWindowStandIn {
        let browser: BrowserStore
        let primary: BrowserPagePool
        let spaceAccess: BrowserSpaceAccessController
        let registry: BrowserPagePoolRegistry
        private(set) var requests: [BrowserQuickWindowRequest] = []
        private(set) var models: [BrowserQuickWindowModel] = []
        private(set) var windows: [NSWindow] = []

        init(browser: BrowserStore, primary: BrowserPagePool, spaceAccess: BrowserSpaceAccessController) {
            self.browser = browser
            self.primary = primary
            self.spaceAccess = spaceAccess
            registry = BrowserPagePoolRegistry(primary: primary, spaceAccess: spaceAccess)
        }

        func open(_ request: BrowserQuickWindowRequest) {
            requests.append(request)
            guard
                let context = BrowserQuickWindowBrowsingContext(
                    for: request, browser: browser, pages: primary, pagePoolRegistry: registry)
            else { return }
            let model = BrowserQuickWindowModel(
                request: request, browser: context.browser, pages: context.pages, spaceAccess: spaceAccess,
                supportsLivePagePromotion: context.supportsLivePagePromotion, preferences: .isolated,
                requestLifecycle: BrowserQuickWindowRequestLifecycle(
                    isCurrent: { $0.id == request.id }, replace: { expected, _ in expected.id == request.id }))
            models.append(model)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 720), styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: BrowserQuickWindowWindowSurface(
                    model: model, spaceAccess: spaceAccess, pagePoolRegistry: registry,
                    dismiss: { [weak window] in window?.close() }, openBrowserWindow: {}
                ))
            windows.append(window)
            window.makeKeyAndOrderFront(nil)
        }

        func closeAll() {
            for window in windows { window.close() }
        }
    }

    private func fixtureURL(_ serverURL: URL, run: String, tab: Int) throws -> URL {
        try XCTUnwrap(
            URL(
                string: "performance.html?run=\(run)&tab=\(tab)",
                relativeTo: serverURL
            )?.absoluteURL
        )
    }

    private func makeSpace(
        profile: BrowsingProfile,
        tabs: [TabState.Seed]
    ) -> SpaceState.Seed {
        SpaceState.Seed(
            profileID: profile.id,
            name: "State",
            symbol: "clock.arrow.circlepath",
            accent: .teal,
            folders: [],
            tabs: tabs,
            browsingPreferences: BrowsingPreferences.seeded(cleanup: .never, blocking: .off)
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(10),
        condition: () async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for \(description).")
    }

    private var fixtureHTML: String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>#status { display: grid; grid-template-columns: 1fr; }</style>
        </head>
        <body>
          <main id="status">loading</main>
          <input id="files" type="file" multiple>
          <script>document.querySelector('#status').textContent = 'ready';</script>
        </body>
        </html>
        """
    }

    private func blockedPopupFixtureHTML() throws -> String {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/BlockedPopups/blocked-popups.html")
        return try String(contentsOf: fixtureURL, encoding: .utf8)
    }

    private var indexedDBRoundTripScript: String {
        """
        return await new Promise((resolve, reject) => {
            const request = indexedDB.open('crest-compatibility', 1);
            request.onupgradeneeded = () => request.result.createObjectStore('values');
            request.onerror = () => reject(request.error);
            request.onsuccess = () => {
                const database = request.result;
                const write = database.transaction('values', 'readwrite');
                write.objectStore('values').put('indexed-db-ready', 'probe');
                write.onerror = () => reject(write.error);
                write.oncomplete = () => {
                    const read = database.transaction('values').objectStore('values').get('probe');
                    read.onerror = () => reject(read.error);
                    read.onsuccess = () => resolve(read.result);
                };
            };
        });
        """
    }

    private var cacheStorageWriteScript: String {
        """
        const cache = await caches.open('crest-space-cache');
        await cache.put('/space-token', new Response('cache-ready'));
        return await (await cache.match('/space-token')).text();
        """
    }

    private var cacheStorageReadScript: String {
        """
        const response = await caches.match('/space-token');
        return response ? await response.text() : null;
        """
    }

    private func loadFixture(on page: WKWebView, origin: URL) async throws {
        let request = URLRequest(url: origin)
        let waiter = NavigationWaiter(webView: page)
        try await waiter.load(simulatedRequest: request, responseHTML: fixtureHTML)
    }

    private func stringResult(from page: WKWebView, script: String) async throws -> String {
        let value = try await page.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap(value as? String)
    }

    private func intResult(from page: WKWebView, script: String) async throws -> Int {
        let value = try await page.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        return try XCTUnwrap((value as? NSNumber)?.intValue)
    }

    private func nullableStringResult(from page: WKWebView, script: String) async throws -> String? {
        let value = try await page.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        if value is NSNull || value == nil { return nil }
        return try XCTUnwrap(value as? String)
    }

    private func removeDataStore(_ identifier: UUID) async {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in
                continuation.resume()
            }
        }
    }
}

@MainActor
private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, any Error>?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func load(simulatedRequest request: URLRequest, responseHTML: String) async throws {
        guard let webView else { throw NavigationWaiterError.releasedWebView }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadSimulatedRequest(request, responseHTML: responseHTML)
        }
    }

    func load(_ request: URLRequest) async throws {
        guard let webView else { throw NavigationWaiterError.releasedWebView }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.load(request)
        }
    }

    func reload() async throws {
        guard let webView else { throw NavigationWaiterError.releasedWebView }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            guard webView.reload() != nil else {
                self.continuation = nil
                continuation.resume(throwing: NavigationWaiterError.navigationUnavailable)
                return
            }
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

private enum NavigationWaiterError: Error {
    case releasedWebView
    case navigationUnavailable
}
