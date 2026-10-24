import AppKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserSharedPageRuntimeTests: XCTestCase {
    func testSnapshotEngineCompletesOnlyCommittedNavigations() throws {
        let tab = TabState.Seed.startPage()
        let space = makeSpace(tabs: [tab])
        let pool = BrowserPagePool(browser: hosting(space))
        defer { pool.reconcile(validTabIDs: []) }
        pool.present(tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        let url = try XCTUnwrap(URL(string: "https://example.com/first"))

        page.receive(BrowserPageNavigationStarted())
        page.receive(BrowserPageLoadingChanged(isLoading: true))
        page.receive(BrowserPageNavigationCommitted(url: url, isLoading: true))
        XCTAssertEqual(page.completedNavigationCount, 0)
        page.receive(BrowserPageLoadingChanged(isLoading: false))
        XCTAssertEqual(page.completedNavigationCount, 1)

        page.receive(BrowserPageNavigationStarted())
        page.receive(BrowserPageLoadingChanged(isLoading: true))
        page.receive(BrowserPageLoadingChanged(isLoading: false))
        XCTAssertEqual(page.completedNavigationCount, 1)

        let section = try XCTUnwrap(URL(string: "https://example.com/first#section"))
        page.receive(BrowserPageNavigationCommitted(url: section, isLoading: false))
        XCTAssertEqual(page.completedNavigationCount, 2)
    }

    func testNormalWindowsShareLivePagesButKeepIndependentSelections() throws {
        let tabs = [TabState.Seed.startPage(), TabState.Seed.startPage()]
        let space = makeSpace(tabs: tabs)
        let runtimeStore = BrowserPageRuntimeStore()
        let browser = hosting(space)
        let first = BrowserPagePool(browser: browser, runtimeStore: runtimeStore)
        let second = BrowserPagePool(browser: browser.makeWindowStore(), runtimeStore: runtimeStore)
        first.present(tab: tabs[0].id, in: space.id)
        let original = try XCTUnwrap(first.activePage)
        second.present(tab: tabs[1].id, in: space.id)
        XCTAssertEqual(first.activeTabID, tabs[0].id)
        XCTAssertEqual(second.activeTabID, tabs[1].id)
        second.present(tab: tabs[0].id, in: space.id)
        XCTAssertTrue(second.activePage === original)
        XCTAssertTrue(first.activePage === original)

        second.setWindowFocused(true)
        XCTAssertNil(first.presentedPage(for: tabs[0].id))
        XCTAssertTrue(first.isMirroringPage(for: tabs[0].id))
        XCTAssertTrue(second.presentedPage(for: tabs[0].id) === original)
        first.setWindowFocused(true)
        XCTAssertTrue(first.presentedPage(for: tabs[0].id) === original)
        XCTAssertTrue(second.isMirroringPage(for: tabs[0].id))
    }

    func testClosingAWindowReleasesOnlyItsClaimAndTransfersRouting() throws {
        let tab = TabState.Seed.startPage()
        let space = makeSpace(tabs: [tab])
        let runtimeStore = BrowserPageRuntimeStore()
        let browser = hosting(space)
        let first = BrowserPagePool(browser: browser, runtimeStore: runtimeStore)
        let second = BrowserPagePool(browser: browser.makeWindowStore(), runtimeStore: runtimeStore)
        first.present(tab: tab.id, in: space.id)
        second.present(tab: tab.id, in: space.id)
        second.setWindowFocused(true)
        let page = try XCTUnwrap(second.activePage)
        page.translation.setActive(true, in: try XCTUnwrap(page.translationDocument))
        page.translation.sourceID = "es"
        page.translation.targetID = "en"
        page.translation.start()
        second.releaseWindowPresentation()
        XCTAssertTrue(first.presentedPage(for: tab.id) === page)
        XCTAssertTrue(page.host === first)
        XCTAssertTrue(first.containsResidentPage(for: tab.id))
        XCTAssertTrue(
            page.translation.isWorking, "Closing a presenter must preserve work still visible in another window.")
        page.translation.suspend()
    }

    func testLiveTransferPreservesPageAndRejectsDifferentProfiles() throws {
        let tab = TabState.Seed.startPage()
        let space = makeSpace(tabs: [tab])
        let source = BrowserPagePool(browser: hosting(space))
        let destination = BrowserPagePool(browser: hosting(space, on: source.browser.core))
        source.present(tab: tab.id, in: space.id)
        let page = try XCTUnwrap(source.activePage)
        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
        var replacement = space
        replacement.profileID = UUID()
        let invalidSpace = try XCTUnwrap(hosting(replacement, on: source.browser.core).spaceModel(space.id))
        XCTAssertFalse(
            destination.transferTabRuntime(
                from: source, matching: assignment, as: try pageTab(assignment, in: source), in: invalidSpace))
        XCTAssertTrue(source.activePage === page)
        XCTAssertTrue(try transfer(assignment, from: source, to: destination))
        XCTAssertFalse(source.containsResidentPage(for: tab.id))
        destination.present(tab: tab.id, in: space.id)
        XCTAssertTrue(destination.activePage === page)
        XCTAssertTrue(page.host === destination)
    }

    func testWindowHandoffAndWorkspaceTransferPreserveTheLiveDocumentAndHistory() async throws {
        let tab = TabState.Seed.startPage()
        let space = makeSpace(tabs: [tab])
        let owner = BrowserPageRuntimeStore()
        let browser = hosting(space)
        let first = BrowserPagePool(browser: browser, runtimeStore: owner)
        let second = BrowserPagePool(browser: browser.makeWindowStore(), runtimeStore: owner)
        let blank = BrowserPagePool(browser: hosting(space, on: browser.core))
        defer {
            first.reconcile(validTabIDs: [])
            blank.closeWindowWorkspace()
        }
        first.present(tab: tab.id, in: space.id)
        let page = try XCTUnwrap(first.activePage)
        let firstHost = BrowserWebHostView()
        let secondHost = BrowserWebHostView()
        let blankHost = BrowserWebHostView()
        let windows = [firstHost, secondHost, blankHost].map { host in
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            return window
        }
        defer { for window in windows { window.close() } }
        firstHost.attach(page.webView, allowsAttachment: true)
        let url = try XCTUnwrap(URL(string: "https://handoff.crest.test/form"))
        page.webView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: "<html><body><textarea id='draft'></textarea></body></html>")
        try await waitUntil { page.webView.url == url && !page.webView.isLoading }
        _ = try await page.webView.evaluateJavaScript(
            "document.getElementById('draft').value = 'unsaved draft'; history.pushState({draft: 7}, '', '#edited');")
        let currentURL = page.webView.url
        let history = page.webView.backForwardList.backList.map(\.url)

        second.present(tab: tab.id, in: space.id)
        second.setWindowFocused(true)
        secondHost.attach(page.webView, allowsAttachment: second.presentedPage(for: tab.id) === page)
        firstHost.attach(page.webView, allowsAttachment: first.presentedPage(for: tab.id) === page)
        XCTAssertTrue(page.webView.window === windows[1])
        XCTAssertTrue(page.webView.superview === secondHost)

        first.setWindowFocused(true)
        firstHost.attach(page.webView, allowsAttachment: first.presentedPage(for: tab.id) === page)
        secondHost.attach(page.webView, allowsAttachment: second.presentedPage(for: tab.id) === page)
        XCTAssertTrue(page.webView.window === windows[0])
        XCTAssertTrue(page.webView.superview === firstHost)

        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
        XCTAssertTrue(try transfer(assignment, from: first, to: blank))
        blank.present(tab: tab.id, in: space.id)
        blankHost.attach(page.webView, allowsAttachment: blank.presentedPage(for: tab.id) === page)
        let staleHost = BrowserWebHostView()
        staleHost.attach(page.webView, allowsAttachment: first.presentedPage(for: tab.id) === page)
        XCTAssertTrue(page.webView.window === windows[2])
        XCTAssertTrue(page.webView.superview === blankHost)
        XCTAssertFalse(first.containsResidentPage(for: tab.id))
        XCTAssertFalse(second.containsResidentPage(for: tab.id))
        XCTAssertTrue(blank.activePage === page)
        XCTAssertEqual(page.webView.url, currentURL)
        XCTAssertEqual(page.webView.backForwardList.backList.map(\.url), history)
        let draft = try await page.webView.evaluateJavaScript("document.getElementById('draft').value") as? String
        let historyState = try await page.webView.evaluateJavaScript("history.state.draft") as? Int
        XCTAssertEqual(draft, "unsaved draft")
        XCTAssertEqual(historyState, 7)
    }

    func testPageCallbacksFollowTheCurrentWorkspaceOwner() throws {
        let tab = TabState.Seed.startPage()
        let space = makeSpace(tabs: [tab])
        let owner = BrowserPageRuntimeStore()
        owner.publishesPageMetadataCentrally = true
        let blankOwner = BrowserPageRuntimeStore()
        blankOwner.publishesPageMetadataCentrally = true
        let browser = hosting(space)
        var links: [String] = []
        let first = BrowserPagePool(
            browser: browser,
            runtimeStore: owner,
            openModifiedLink: { _, _, _ in
                links.append("first")
                return nil
            })
        let second = BrowserPagePool(
            browser: browser.makeWindowStore(),
            runtimeStore: owner,
            openModifiedLink: { _, _, _ in
                links.append("second")
                return nil
            })
        let blank = BrowserPagePool(
            browser: hosting(space, on: browser.core),
            runtimeStore: blankOwner,
            openModifiedLink: { _, _, _ in
                links.append("blank")
                return nil
            })
        defer {
            first.reconcile(validTabIDs: [])
            blank.closeWindowWorkspace()
        }
        first.present(tab: tab.id, in: space.id)
        let page = try XCTUnwrap(first.activePage)
        second.present(tab: tab.id, in: space.id)
        second.setWindowFocused(true)
        let request = URLRequest(url: try XCTUnwrap(URL(string: "https://callback.crest.test/")))
        page.openModifiedLink(request, space.id, false)
        XCTAssertEqual(links, ["second"])

        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
        XCTAssertTrue(try transfer(assignment, from: second, to: blank))
        blank.present(tab: tab.id, in: space.id)
        page.openModifiedLink(request, space.id, false)
        XCTAssertEqual(links, ["second", "blank"])
    }

    func testNativeTabMovePreservesItsLoadedModelAcrossWorkspaceOwners() throws {
        let tab = TabState.Seed(title: "Getting Started", url: nil, nativeContent: .gettingStarted, placement: .current)
        let space = makeSpace(tabs: [tab])
        let source = BrowserPagePool(browser: hosting(space))
        let destination = BrowserPagePool(browser: hosting(space, on: source.browser.core))
        source.present(tab: tab.id, in: space.id)
        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
        let runtime = try XCTUnwrap(source.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        let model = runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }
        model.chapter = .splitView
        XCTAssertTrue(try transfer(assignment, from: source, to: destination))
        destination.present(tab: tab.id, in: space.id)
        XCTAssertFalse(source.nativeTabs.contains(assignment))
        XCTAssertTrue(destination.nativeTabs.runtime(matching: assignment, content: .gettingStarted) === runtime)
        XCTAssertEqual(
            runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }.chapter, .splitView)
    }

    func testAnUnloadedTabTransfersItsArchivedHistoryWithoutLeavingSourceState() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "crest-window-tab-state-\(UUID())")
        let archive = BrowserTabStateArchive(rootDirectory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tab = TabState.Seed.startPage()
        let space = makeSpace(tabs: [tab])
        let source = BrowserPagePool(
            browser: hosting(space), usesEphemeralWebsiteDataStores: false, tabStateArchive: archive)
        // A window over a workspace that borrows the Space, as tearing a tab
        // off into a window of its own opens.
        let spaceAssignment = BrowserSpaceRuntimeAssignment(space: space)
        let destination = BrowserPagePool(
            browser: try XCTUnwrap(source.browser.makeTemporaryWindowStore(in: spaceAssignment)))
        defer {
            source.reconcile(validTabIDs: [])
            destination.closeWindowWorkspace()
        }
        source.present(tab: tab.id, in: space.id)
        let original = try XCTUnwrap(source.activePage)
        let firstURL = try XCTUnwrap(URL(string: "https://unloaded-transfer.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://unloaded-transfer.crest.test/two"))
        for url in [firstURL, secondURL] {
            original.webView.loadSimulatedRequest(
                URLRequest(url: url), responseHTML: "<html><body>History</body></html>")
            try await waitUntil { original.webView.url == url && !original.webView.isLoading }
        }
        source.unloadPage(for: tab.id)
        await archive.flushPendingWrites()
        XCTAssertNotNil(archive.archivedState(profileID: space.profileID, tabID: tab.id))
        let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)

        // The core moves the tab first, with the address its page reached, and
        // then its archived page state follows it, as the window coordinator
        // moves them.
        XCTAssertTrue(
            source.browser.transferTab(tab.id, matching: spaceAssignment, to: destination.browser, in: spaceAssignment))
        XCTAssertTrue(
            destination.transferTabRuntime(
                from: source, matching: assignment, as: try pageTab(assignment, in: destination),
                in: try XCTUnwrap(destination.browser.spaceModel(space.id))))
        await source.flushPendingTabStateWrites()
        XCTAssertNil(archive.archivedState(profileID: space.profileID, tabID: tab.id))
        destination.present(tab: tab.id, in: space.id)
        let restored = try XCTUnwrap(destination.activePage)
        XCTAssertFalse(restored === original)
        XCTAssertEqual(restored.webView.url, secondURL)
        XCTAssertEqual(restored.webView.backForwardList.backList.map(\.url), [firstURL])
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for the live page update.")
    }

    /// A window over a session holding `space`, on `core` when another
    /// workspace of the test already hosts pages there.
    private func hosting(_ space: SpaceState.Seed, on core: CrestCore = .hostingPages()) -> BrowserStore {
        .hostingPages(SessionState.Seed(spaces: [space]), core: core)
    }

    /// The tab `assignment` names as `pool`'s window holds it, for its page.
    private func pageTab(_ assignment: BrowserTabRuntimeAssignment, in pool: BrowserPagePool) throws -> BrowserPageTab {
        let tab = try XCTUnwrap(pool.browser.spaceModel(assignment.spaceID)?.tabs.model(assignment.tabID))
        return BrowserPageTab(tab, images: pool.browser.core.state.favicons)
    }

    /// Moves the page of the tab `assignment` names from `source`'s window to
    /// `destination`'s, as dragging a tab between windows does.
    private func transfer(
        _ assignment: BrowserTabRuntimeAssignment, from source: BrowserPagePool, to destination: BrowserPagePool
    ) throws -> Bool {
        let space = try XCTUnwrap(destination.browser.spaceModel(assignment.spaceID))
        return destination.transferTabRuntime(
            from: source, matching: assignment, as: try pageTab(assignment, in: source), in: space)
    }

    private func makeSpace(tabs: [TabState.Seed]) -> SpaceState.Seed {
        SpaceState.Seed(
            name: "Shared", symbol: "globe", accent: .indigo,
            folders: [], tabs: tabs)
    }
}
