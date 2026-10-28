import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserContentBlockingTests: XCTestCase {
    // MARK: - Actions - Protection

    func testInitialNavigationWaitsForRulesAndToggleReloadsOnlyPresentedPages() async throws {
        let fixture = try extensionFixture()
        let server = try BrowserPrivacyHTTPServer()
        server.overrideResponse = { request in
            let body =
                request.path == "/blocked.js"
                ? "window.trackerLoaded = true;"
                : "<html><head><link rel='icon' href='data:,'></head><body><div id='ad'>Ad</div><script src='/blocked.js'></script></body></html>"
            return (
                "200 OK", "Content-Type: \(request.path == "/blocked.js" ? "application/javascript" : "text/html")\r\n",
                Data(body.utf8)
            )
        }
        try await server.start()
        defer { server.stop() }
        let address = server.url(host: "127.0.0.1", path: "/document")
        let first = TabState.Seed(title: "Protected", url: address, placement: .current)
        let second = TabState.Seed(title: "Protected", url: address, placement: .current)
        let space = SpaceState.Seed(name: "Protected", tabs: [first, second])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: first.id],
            core: .hostingPages(contentBlocking: WebKitContentBlocking(resourceURL: fixture)))
        let pool = BrowserPagePool(browser: browser)
        defer { for id in pool.retainedTabIDs { pool.unloadPage(for: id) } }
        pool.select()
        let background = try XCTUnwrap(pool.activePage)
        try await waitUntil { background.completedNavigationCount > 0 }
        let hidden =
            try await background.webView.evaluateJavaScript("getComputedStyle(document.querySelector('#ad')).display")
            as? String
        let tracker = try await background.webView.evaluateJavaScript("window.trackerLoaded === true") as? Bool
        XCTAssertEqual(hidden, "none")
        XCTAssertEqual(tracker, false)
        XCTAssertFalse(server.requests.contains { $0.path == "/blocked.js" })
        XCTAssertTrue(background.isContentBlockingActive)
        pool.present(tab: second.id, in: space.id)
        let presented = try XCTUnwrap(pool.activePage)
        try await waitUntil { presented.completedNavigationCount > 0 }
        await pool.reconcileContentBlocking()
        let backgroundCount = background.completedNavigationCount
        let presentedCount = presented.completedNavigationCount
        var preferences = try XCTUnwrap(browser.spaceModel(space.id)).settings.browsingPreferences
        preferences.contentBlocking = .off
        browser.updateBrowsingPreferences(preferences, in: space.id)
        await pool.reconcileContentBlocking()
        try await waitUntil { presented.completedNavigationCount > presentedCount }
        XCTAssertEqual(background.completedNavigationCount, backgroundCount)
        let allowed = try await presented.webView.evaluateJavaScript("window.trackerLoaded === true") as? Bool
        XCTAssertEqual(allowed, true)
        XCTAssertFalse(presented.isContentBlockingActive)
        XCTAssertFalse(background.isContentBlockingActive)
    }

    func testProfilesNeverExposeEachOthersTabsAndPrivateControllersAreEphemeral() async throws {
        let fixture = try extensionFixture()
        let firstTab = TabState.Seed(title: "Blank", url: URL(string: "about:blank"), placement: .current)
        let secondTab = TabState.Seed(title: "Blank", url: URL(string: "about:blank"), placement: .current)
        let first = SpaceState.Seed(name: "First", tabs: [firstTab])
        let second = SpaceState.Seed(name: "Second", tabs: [secondTab])
        let manager = WebKitContentBlocking(resourceURL: fixture)
        let core = CrestCore.hostingPages(contentBlocking: manager)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [first, second]), core: core)
        let pool = BrowserPagePool(browser: browser)
        defer { for id in pool.retainedTabIDs { pool.unloadPage(for: id) } }
        pool.present(tab: firstTab.id, in: first.id)
        let firstPage = try XCTUnwrap(pool.activePage?.webKitEnginePage)
        pool.present(tab: secondTab.id, in: second.id)
        let secondPage = try XCTUnwrap(pool.activePage?.webKitEnginePage)
        try await firstPage.contentBlocker.setEnabled(true)
        try await secondPage.contentBlocker.setEnabled(true)
        let firstContext = try XCTUnwrap(firstPage.contentBlocker.controller.extensionContexts.first)
        let tabs = firstPage.contentBlocker.tabs(for: firstContext)
        XCTAssertEqual(tabs.count, 1)
        XCTAssertTrue(tabs.first as? WebKitEnginePage === firstPage)
        XCTAssertFalse(firstPage.contentBlocker.controller === secondPage.contentBlocker.controller)
        let binding = try XCTUnwrap(core.engines.webKit)
        let privateBlocker = manager.blocker(
            profileID: UUID(), dataStore: .nonPersistent(), isPrivate: true, binding: binding)
        try await privateBlocker.setEnabled(true)
        XCTAssertFalse(privateBlocker.controller.configuration.isPersistent)
        XCTAssertTrue(try XCTUnwrap(privateBlocker.controller.extensionContexts.first).hasAccessToPrivateData)
        pool.unloadPage(for: firstTab.id)
        XCTAssertTrue(firstPage.contentBlocker.tabs(for: firstContext).isEmpty)
        try await manager.removeData(profileID: privateBlocker.profileID, isEphemeral: true)
        XCTAssertTrue(privateBlocker.controller.extensionContexts.isEmpty)
    }

    func testClosingDuringStartupDeclinesNavigationWithoutWaitingForExtension() async throws {
        let fixture = try extensionFixture(delay: 800)
        let tab = TabState.Seed(title: "Blank", url: URL(string: "about:blank"), placement: .current)
        let space = SpaceState.Seed(name: "Starting", tabs: [tab])
        let core = CrestCore.hostingPages(contentBlocking: WebKitContentBlocking(resourceURL: fixture))
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]), core: core)
        let pool = BrowserPagePool(browser: browser)
        pool.present(tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage?.webKitEnginePage)
        var answers: [Bool] = []
        page.prepareNavigation { answers.append($0) }
        pool.unloadPage(for: tab.id)
        XCTAssertEqual(answers, [false])
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(answers, [false])
        XCTAssertTrue(page.isClosed)
    }

    func testBundledUbolStartsInThePagesOwnProfile() async throws {
        let tab = TabState.Seed(title: "Blank", url: URL(string: "about:blank"), placement: .current)
        let space = SpaceState.Seed(name: "Bundled", tabs: [tab])
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let pool = BrowserPagePool(browser: browser)
        defer { pool.unloadPage(for: tab.id) }
        pool.present(tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage?.webKitEnginePage)
        try await page.contentBlocker.setEnabled(true)
        XCTAssertTrue(page.isContentBlockingActive)
        XCTAssertNil(page.contentBlocker.errorDescription)
        XCTAssertTrue(
            page.contentBlocker.controller.configuration.defaultWebsiteDataStore
                === page.webView.configuration.websiteDataStore)
    }

    func testMissingBundleRemainsVisibleAsAnError() async {
        let manager = WebKitContentBlocking(resourceURL: nil)
        await manager.prepare()
        XCTAssertNotNil(manager.errorDescription)
        await manager.prepare()
        XCTAssertNotNil(manager.errorDescription)
    }

    // MARK: - Actions - Fixtures

    private func extensionFixture(delay: Int = 100) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("crest-blocker-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let files = [
            "manifest.json":
                #"{"manifest_version":3,"name":"Crest blocker fixture","version":"1.0","permissions":["declarativeNetRequest","declarativeNetRequestWithHostAccess","scripting","nativeMessaging"],"host_permissions":["<all_urls>"],"background":{"scripts":["background.js"],"type":"module","persistent":false},"declarative_net_request":{"rule_resources":[{"id":"fixture","enabled":true,"path":"rules.json"}]}}"#,
            "rules.json":
                #"[{"id":1,"priority":1,"action":{"type":"block"},"condition":{"urlFilter":"/blocked.js","resourceTypes":["script"]}}]"#,
            "hide.css": "#ad { display: none !important; }",
            "background.js": """
            try {
              await new Promise(resolve => setTimeout(resolve, \(delay)));
              await browser.scripting.registerContentScripts([{id:'cosmetics',matches:['<all_urls>'],css:['hide.css'],runAt:'document_start'}]);
              await browser.runtime.sendNativeMessage('com.pauldavis.crest',{event:'ready'});
            } catch(error) {
              await browser.runtime.sendNativeMessage('com.pauldavis.crest',{event:'error',message:String(error)});
            }
            """,
        ]
        for (name, contents) in files {
            try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return directory
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Content blocking did not reach the expected state")
        throw CocoaError(.coderReadCorrupt)
    }
}
