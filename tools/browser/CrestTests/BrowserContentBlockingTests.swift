import Foundation
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserContentBlockingTests: XCTestCase {
    @MainActor
    func testBalancedProtectionCompilesOnlyCrestsBundledRuleList() async throws {
        let store = try isolatedRuleListStore()
        defer { store.remove() }
        let compiler = RecordingBuiltInRuleListCompiler()
        let core = CrestCore()
        let provider = BrowserContentRuleListProvider(
            core: core,
            ruleListStore: store.store,
            compiler: compiler
        )

        let ruleLists = try await provider.balancedRuleLists()
        let rules = try core.query(BalancedProtectionRules())

        XCTAssertEqual(ruleLists.map(\.identifier), [rules.identifier])
        XCTAssertEqual(compiler.identifiers, [rules.identifier])
        XCTAssertEqual(compiler.sources, [rules.source])
    }

    func testPagePoolReconcilesThePolicyAcrossResidentAndRecoveredTransientPages() async throws {
        let store = try isolatedRuleListStore()
        defer { store.remove() }
        let ruleList = try await BrowserContentRuleListCompiler.compile(
            identifier: "com.pauldavis.crest.tests.pool-reconciliation.\(UUID().uuidString)",
            source: blockingRuleSource(matching: "crest-pool-reconciliation\\.js$"),
            store: store.store
        )
        let provider = StubContentRuleListProvider(generations: [[ruleList]])
        let firstTab = TabState.Seed.startPage()
        let firstSpace = contentBlockingSpace(name: "Protected", tab: firstTab)
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [firstSpace]), showing: firstSpace.id, tabs: [firstSpace.id: firstTab.id],
            core: .hostingPages(contentRuleLists: provider))
        let pool = BrowserPagePool(browser: browser, browsingMode: .privateBrowsing)
        defer {
            for tabID in pool.retainedTabIDs {
                pool.unloadPage(for: tabID)
            }
        }

        await pool.prepareContentBlocking()
        XCTAssertNil(
            pool.contentBlockingErrorDescription,
            pool.contentBlockingErrorDescription ?? ""
        )
        pool.select()
        XCTAssertEqual(pool.activePage?.isContentBlockingActive, true)
        let transientLease = try XCTUnwrap(
            pool.makeTransientPageLease(
                url: URL(string: "about:blank")!,
                in: try XCTUnwrap(browser.spaceModel(firstSpace.id))
            )
        )
        XCTAssertEqual(transientLease.page?.isContentBlockingActive, true)

        var preferences = try XCTUnwrap(browser.spaceModel(firstSpace.id)).settings.browsingPreferences
        preferences.contentBlocking = .off
        browser.updateBrowsingPreferences(preferences, in: firstSpace.id)
        await pool.reconcileContentBlocking()

        XCTAssertEqual(pool.activePage?.isContentBlockingActive, false)
        XCTAssertEqual(transientLease.page?.isContentBlockingActive, false)

        transientLease.setActive(false)
        pool.relieveMemoryPressure(.warning)
        XCTAssertNil(transientLease.page)
        transientLease.restore()
        XCTAssertEqual(transientLease.page?.isContentBlockingActive, false)

    }

    func testTurningOffCrestProtectionPreservesAnotherInstalledRuleList() async throws {
        let crestIdentifier = "com.pauldavis.crest.tests.owned-rules.\(UUID().uuidString)"
        let extensionIdentifier = "com.pauldavis.crest.tests.extension-rules.\(UUID().uuidString)"
        let crestRuleList = try await BrowserContentRuleListCompiler.compile(
            identifier: crestIdentifier,
            source: blockingRuleSource(matching: "crest-script\\.js$")
        )
        let extensionRuleList = try await BrowserContentRuleListCompiler.compile(
            identifier: extensionIdentifier,
            source: blockingRuleSource(matching: "extension-script\\.js$")
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("crest-exact-rule-removal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        do {
            let documentURL = directory.appendingPathComponent("index.html")
            try Data(
                #"""
                <!doctype html><html><body>
                  <script src="crest-script.js"></script>
                  <script src="extension-script.js"></script>
                </body></html>
                """#.utf8
            ).write(to: documentURL)
            try Data("window.crestOwnedScriptLoaded = true;".utf8).write(
                to: directory.appendingPathComponent("crest-script.js")
            )
            try Data("window.crestExtensionScriptLoaded = true;".utf8).write(
                to: directory.appendingPathComponent("extension-script.js")
            )

            let space = try XCTUnwrap(SessionState.Seed.preview.spaces.first)
            let browser = BrowserStore.hostingPages(.preview)
            // A popup shares its opener's user content controller, so it holds
            // rule lists Crest did not install.
            let opener = try XCTUnwrap(
                browser.openWebKitPage(in: space.id, for: try XCTUnwrap(space.tabs.first).id))
            defer { opener.core.release(keepingState: false) }
            let configuration = BrowserPageConfiguration.make(
                for: BrowsingProfile(id: space.profileID),
                websiteDataStore: .nonPersistent(),
                contentRuleList: crestRuleList
            )
            configuration.userContentController.add(extensionRuleList)
            let page = try XCTUnwrap(
                browser.openWebKitPopup(
                    from: opener.webKit, configuration: configuration,
                    loading: URLRequest(url: try XCTUnwrap(URL(string: "about:blank")))
                ).map {
                    opened in
                    BrowserPage(
                        corePage: opened.core,
                        webKitPage: opened.webKit,
                        dialogPresenter: BrowserDialogPresenter(),
                        downloadCenter: BrowserDownloadCenter(),
                        permissionCenter: BrowserSitePermissionCenter(),
                        spaceID: space.id,
                        profileID: space.profileID,
                        spaceName: space.settings.name,
                        contentRuleList: crestRuleList,
                        openNewTab: { _ in }
                    )
                })
            defer { page.release(keepingState: false) }

            page.applyContentBlocking(policy: .off, balancedRuleList: crestRuleList)
            let startingNavigationCount = page.completedNavigationCount
            page.webView.loadFileURL(documentURL, allowingReadAccessTo: directory)
            try await waitForNavigation(after: startingNavigationCount, on: page)

            let crestScriptLoaded =
                try await page.webView.evaluateJavaScript(
                    "window.crestOwnedScriptLoaded === true"
                ) as? Bool
            let extensionScriptLoaded =
                try await page.webView.evaluateJavaScript(
                    "window.crestExtensionScriptLoaded === true"
                ) as? Bool
            XCTAssertEqual(crestScriptLoaded, true)
            XCTAssertEqual(extensionScriptLoaded, false)
        } catch {
            await BrowserContentRuleListCompiler.remove(identifier: crestIdentifier)
            await BrowserContentRuleListCompiler.remove(identifier: extensionIdentifier)
            throw error
        }
        await BrowserContentRuleListCompiler.remove(identifier: crestIdentifier)
        await BrowserContentRuleListCompiler.remove(identifier: extensionIdentifier)
    }

    func testFilterListUpdateSwapsRulesWithoutReloadingResidentPages() async throws {
        let documents = try TrackerDocuments()
        defer { documents.remove() }
        let store = try isolatedRuleListStore()
        defer { store.remove() }
        let firstGeneration = try await BrowserContentRuleListCompiler.compile(
            identifier: "com.pauldavis.crest.tests.first-generation.\(UUID().uuidString)",
            source: blockingRuleSource(matching: "first-tracker\\.js$"),
            store: store.store
        )
        let secondGeneration = try await BrowserContentRuleListCompiler.compile(
            identifier: "com.pauldavis.crest.tests.second-generation.\(UUID().uuidString)",
            source: blockingRuleSource(matching: "second-tracker\\.js$"),
            store: store.store
        )
        let provider = StubContentRuleListProvider(
            generations: [[firstGeneration], [secondGeneration]]
        )
        let activeTab = TabState.Seed.startPage()
        let backgroundTab = TabState.Seed.startPage()
        let space = contentBlockingSpace(
            name: "Protected",
            tabs: [activeTab, backgroundTab]
        )
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: backgroundTab.id],
            core: .hostingPages(contentRuleLists: provider))
        let pool = BrowserPagePool(browser: browser, browsingMode: .privateBrowsing)
        defer {
            for tabID in pool.retainedTabIDs {
                pool.unloadPage(for: tabID)
            }
        }

        await pool.prepareContentBlocking()
        pool.select()
        let backgroundPage = try XCTUnwrap(pool.activePage)
        pool.present(tab: activeTab.id, in: space.id)
        let activePage = try XCTUnwrap(pool.activePage)
        XCTAssertFalse(activePage === backgroundPage)

        for page in [activePage, backgroundPage] {
            try await documents.load(into: page)
            let trackers = try await documents.trackerState(in: page)
            XCTAssertEqual(trackers, [false, true])
            try await documents.markSentinel(in: page)
        }
        let activeNavigationCount = activePage.completedNavigationCount
        let backgroundNavigationCount = backgroundPage.completedNavigationCount

        await pool.reloadContentBlocking()

        // The swap must reach both pages without disturbing either document.
        try await Task.sleep(for: .milliseconds(400))
        for (page, navigationCount) in [
            (activePage, activeNavigationCount),
            (backgroundPage, backgroundNavigationCount),
        ] {
            let keptSentinel = try await documents.hasSentinel(in: page)
            let trackers = try await documents.trackerState(in: page)
            XCTAssertEqual(page.completedNavigationCount, navigationCount)
            XCTAssertFalse(page.live.isLoading)
            XCTAssertTrue(keptSentinel)
            XCTAssertEqual(trackers, [false, true])
            XCTAssertEqual(page.isContentBlockingActive, true)
        }

        // The next navigation in each page is the one that answers to the new
        // rules: the first tracker is allowed again and the second is blocked.
        for page in [activePage, backgroundPage] {
            try await documents.load(into: page)
            let trackers = try await documents.trackerState(in: page)
            XCTAssertEqual(trackers, [true, false])
        }
    }

    private func isolatedRuleListStore() throws -> IsolatedRuleListStore {
        try IsolatedRuleListStore()
    }

    private func blockingRuleSource(matching urlFilter: String) -> String {
        let rules: [[String: Any]] = [
            [
                "trigger": [
                    "url-filter": urlFilter,
                    "resource-type": ["script"],
                ],
                "action": ["type": "block"],
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: rules)
        return String(decoding: data, as: UTF8.self)
    }

    private func contentBlockingSpace(
        name: String,
        tab: TabState.Seed
    ) -> SpaceState.Seed {
        contentBlockingSpace(name: name, tabs: [tab])
    }

    private func contentBlockingSpace(
        name: String,
        tabs: [TabState.Seed]
    ) -> SpaceState.Seed {
        SpaceState.Seed(
            name: name,
            symbol: "shield",
            accent: .indigo,
            folders: [],
            tabs: tabs
        )
    }

    private func waitForNavigation(
        after startingCount: Int,
        on page: BrowserPage
    ) async throws {
        for _ in 0..<100 {
            if page.completedNavigationCount > startingCount { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("Timed out waiting for the local content-blocking document")
    }
}

private enum ContentBlockingTestError: Error {
    case unavailableRuleListStore
    case navigationTimedOut
}

@MainActor
private final class RecordingBuiltInRuleListCompiler:
    BrowserContentRuleListCompiling
{
    private(set) var identifiers: [String] = []
    private(set) var sources: [String] = []

    func compile(
        identifiers: [String],
        sources: [String],
        store: WKContentRuleListStore
    ) async throws -> [WKContentRuleList] {
        self.identifiers = identifiers
        self.sources = sources
        return try await BrowserContentRuleListCompilerAdapter().compile(
            identifiers: identifiers,
            sources: sources,
            store: store
        )
    }
}

/// A rule-list store of its own, so a test never sweeps or reads compiled lists
/// belonging to the app or to another test.
@MainActor
private struct IsolatedRuleListStore {
    let store: WKContentRuleListStore
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "crest-rule-list-store-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        guard let store = WKContentRuleListStore(url: directory) else {
            throw ContentBlockingTestError.unavailableRuleListStore
        }
        self.store = store
    }

    func availableIdentifiers() async -> [String] {
        await BrowserContentRuleListCompiler.availableIdentifiers(store: store)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A local document with two tracker scripts and a sentinel a reload would wipe,
/// which is how these tests tell a rule-list swap from a reload.
@MainActor
private struct TrackerDocuments {
    private let directory: URL
    private let documentURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "crest-content-blocking-swap-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        documentURL = directory.appendingPathComponent("index.html")
        try Data(
            #"""
            <!doctype html><html><body>
              <p id="status">ready</p>
              <script src="first-tracker.js"></script>
              <script src="second-tracker.js"></script>
            </body></html>
            """#.utf8
        ).write(to: documentURL)
        try Data("window.crestFirstTrackerLoaded = true;".utf8).write(
            to: directory.appendingPathComponent("first-tracker.js")
        )
        try Data("window.crestSecondTrackerLoaded = true;".utf8).write(
            to: directory.appendingPathComponent("second-tracker.js")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func load(into page: BrowserPage) async throws {
        let startingCount = page.completedNavigationCount
        page.webView.loadFileURL(documentURL, allowingReadAccessTo: directory)
        for _ in 0..<200 {
            if page.completedNavigationCount > startingCount { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw ContentBlockingTestError.navigationTimedOut
    }

    /// Whether each tracker script ran in the document that is loaded now.
    func trackerState(in page: BrowserPage) async throws -> [Bool] {
        [
            try await boolean("window.crestFirstTrackerLoaded === true", in: page),
            try await boolean("window.crestSecondTrackerLoaded === true", in: page),
        ]
    }

    func markSentinel(in page: BrowserPage) async throws {
        _ = try await page.webView.evaluateJavaScript(
            "window.crestSentinel = 'kept'; true"
        )
    }

    func hasSentinel(in page: BrowserPage) async throws -> Bool {
        try await boolean("window.crestSentinel === 'kept'", in: page)
    }

    private func boolean(_ script: String, in page: BrowserPage) async throws -> Bool {
        try await page.webView.evaluateJavaScript(script) as? Bool ?? false
    }
}

/// Hands out one rule-list generation per request, standing in for the provider
/// recompiling after a filter-list update.
@MainActor
private final class StubContentRuleListProvider: BrowserContentRuleListProviding {
    private let generations: [[WKContentRuleList]]
    private var requestCount = 0

    init(generations: [[WKContentRuleList]]) {
        precondition(!generations.isEmpty)
        self.generations = generations
    }

    func balancedRuleLists() async throws -> [WKContentRuleList] {
        defer { requestCount += 1 }
        return generations[min(requestCount, generations.count - 1)]
    }
}

extension BrowserStore {
    /// The page WebKit builds from `configuration` for a popup `opener`, a
    /// tab's page this window opened, offers the core, as a popup WebKit made
    /// would be, for a test that hosts the page itself. Nil when the core
    /// refuses it.
    fileprivate func openWebKitPopup(
        from opener: WebKitEnginePage, configuration: WKWebViewConfiguration, loading request: URLRequest
    ) -> (core: CorePage, webKit: WebKitEnginePage)? {
        guard let popup = opener.offer(WebKitPopup(configuration: configuration), for: request, foreground: false),
            let opened = core.engines.host(popup.id)
        else { return nil }
        return (opened.page, popup)
    }
}
