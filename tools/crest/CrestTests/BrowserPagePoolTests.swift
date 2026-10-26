import AppKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPagePoolTests: XCTestCase {

    func testCredentialAccessReconcilesAcrossAnExistingSpacePage() throws {
        let browser = BrowserStore.hostingPages(.preview)
        let pool = BrowserPagePool(browser: browser)
        pool.select()
        XCTAssertTrue(try XCTUnwrap(pool.activePage).isCredentialAccessEnabled)

        let space = try XCTUnwrap(browser.shownSpace)
        browser.updateCredentialPreferences(
            CredentialPreferences(
                isEnabled: false, syncsCrestPasswordsWithICloud: false, alsoOffersSaveToSystemPasswords: false),
            in: space.id)
        pool.reconcileCredentialAccess()

        XCTAssertFalse(try XCTUnwrap(pool.activePage).isCredentialAccessEnabled)
    }

    func testPrivatePoolReusesOneEphemeralStorePerSpaceWithoutCredentialsOrExtensions() throws {
        let firstTab = TabState.Seed.startPage()
        let secondTab = TabState.Seed.startPage()
        let firstSpace = makeSpace(tabs: [firstTab], selectedTabID: firstTab.id)
        let secondSpace = makeSpace(tabs: [secondTab], selectedTabID: secondTab.id)
        let pool = BrowserPagePool(
            browser: hosting(firstSpace, secondSpace),
            browsingMode: .privateBrowsing
        )

        present(pool, tab: firstTab.id, in: firstSpace.id)
        let firstPage = try XCTUnwrap(pool.activePage)
        let firstStore = firstPage.webView.configuration.websiteDataStore

        XCTAssertFalse(firstStore.isPersistent)
        XCTAssertNil(firstStore.identifier)
        XCTAssertNil(firstPage.webView.configuration.webExtensionController)
        // The order the page installs its scripts in is not the contract.
        XCTAssertEqual(
            firstPage.webView.configuration.userContentController.userScripts
                .map(\.source).sorted(),
            [
                BrowserPictureInPictureScript.source,
                WebKitMediaActivityBridge.source,
                BrowserLinkHoverContentBridge.source,
                BrowserLinkDragContentBridge.source,
                BrowserLinkContextContentBridge.source,
                BrowserBlockedPopupContentBridge.source,
                BrowserGeolocationContentBridge.source,
            ].sorted(),
            "Private pages allow browsing bridges, including link pulls, without credential or extension scripts."
        )

        present(pool, tab: secondTab.id, in: secondSpace.id)
        let secondStore = try XCTUnwrap(pool.activePage)
            .webView.configuration.websiteDataStore
        XCTAssertFalse(firstStore === secondStore)

        present(pool, tab: firstTab.id, in: firstSpace.id)
        let restoredFirstStore = try XCTUnwrap(pool.activePage)
            .webView.configuration.websiteDataStore
        XCTAssertTrue(firstStore === restoredFirstStore)
    }

    func testXCTestStandardPoolNeverUsesTheInstalledWebsiteDataStore() throws {
        let tab = TabState.Seed.startPage()
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let pool = BrowserPagePool(browser: hosting(space))

        present(pool, tab: tab.id, in: space.id)
        let store = try XCTUnwrap(
            pool.activePage?.webView.configuration.websiteDataStore
        )

        XCTAssertFalse(store.isPersistent)
        XCTAssertNil(store.identifier)
    }

    func testDeletingASpacesRuntimeDataPreservesAnotherSpacesPageAndPermissions() async throws {
        let deletedTab = TabState.Seed.startPage()
        let retainedTab = TabState.Seed.startPage()
        let deletedSpace = makeSpace(
            tabs: [deletedTab],
            selectedTabID: deletedTab.id
        )
        let retainedSpace = makeSpace(
            tabs: [retainedTab],
            selectedTabID: retainedTab.id
        )
        let permissionCenter = BrowserSitePermissionCenter()
        let remover = RecordingWebsiteDataStoreRemover()
        let pool = BrowserPagePool(
            browser: hosting(deletedSpace, retainedSpace, on: .hostingPages(profileStores: remover)),
            usesEphemeralWebsiteDataStores: false,
            permissionCenter: permissionCenter
        )
        let origin = SiteOrigin(
            scheme: "https",
            host: "camera.crest.test",
            port: 443
        )
        permissionCenter.setDecision(
            .grantPersistently,
            for: .camera,
            origin: origin,
            in: deletedSpace.id
        )
        permissionCenter.setDecision(
            .denyPersistently,
            for: .camera,
            origin: origin,
            in: retainedSpace.id
        )
        present(pool, tab: deletedTab.id, in: deletedSpace.id)
        present(pool, tab: retainedTab.id, in: retainedSpace.id)

        try await pool.deleteData(for: BrowserSpaceRuntimeAssignment(space: deletedSpace))

        XCTAssertFalse(pool.retainedTabIDs.contains(deletedTab.id))
        XCTAssertTrue(pool.retainedTabIDs.contains(retainedTab.id))
        XCTAssertEqual(pool.activeTabID, retainedTab.id)
        XCTAssertTrue(permissionCenter.records(in: deletedSpace.id).isEmpty)
        XCTAssertEqual(
            permissionCenter.records(in: retainedSpace.id).map(\.decision),
            [.denyPersistently]
        )
        XCTAssertEqual(remover.removedProfileIDs, [deletedSpace.profileID])
    }

    func testPoolRoutesAcceptedHTTPAuthenticationBackToTheExactSpaceStore() async throws {
        let tab = TabState.Seed(title: "Protected", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let protectionSpace = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 443,
            protocol: "https",
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let credentialProtectionSpace = try XCTUnwrap(
            BrowserHTTPAuthenticationProtectionSpace(protectionSpace)
        )
        let storedCredential = BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: space.id,
                origin: credentialProtectionSpace.origin,
                scope: credentialProtectionSpace.credentialScope,
                username: "member"
            ),
            password: "stored-secret"
        )
        var savedRequests: [(BrowserHTTPAuthenticationSaveRequest, UUID)] = []
        let saved = expectation(description: "Accepted credential is marked used")
        let pool = BrowserPagePool(
            browser: hosting(space),
            loadHTTPAuthenticationCredential: { requestedProtectionSpace, spaceID in
                XCTAssertEqual(spaceID, space.id)
                XCTAssertEqual(requestedProtectionSpace, credentialProtectionSpace)
                return storedCredential
            },
            saveHTTPAuthenticationCredential: { request, spaceID in
                savedRequests.append((request, spaceID))
                saved.fulfill()
            }
        )
        present(pool, tab: tab.id, in: space.id)
        let page = try XCTUnwrap(pool.activePage)
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: PagePoolAuthenticationChallengeSenderStub()
        )

        let resolution = await withCheckedContinuation { continuation in
            page.webView(page.webView, didReceive: challenge) { disposition, credential in
                continuation.resume(returning: (disposition, credential))
            }
        }

        XCTAssertEqual(resolution.0, .useCredential)
        XCTAssertEqual(resolution.1?.user, "member")
        XCTAssertEqual(resolution.1?.password, "stored-secret")
        XCTAssertTrue(savedRequests.isEmpty)

        page.webView(page.webView, didFinish: nil)
        await fulfillment(of: [saved], timeout: 1)

        XCTAssertEqual(savedRequests.count, 1)
        XCTAssertEqual(savedRequests.first?.0.replacing, storedCredential.descriptor)
        XCTAssertEqual(savedRequests.first?.1, space.id)
    }

    func testPrivatePopupAdoptionStaysInsideThePrivatePool() throws {
        let popupURL = try XCTUnwrap(URL(string: "https://example.com/popup"))
        let regular = try makePopupContext()
        let privateContext = try makePopupContext(browsingMode: .privateBrowsing)

        let popupWebView = try XCTUnwrap(
            privateContext.requestPopup(url: popupURL, navigationType: .linkActivated)
        )

        XCTAssertFalse(popupWebView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(privateContext.store.shownSpace?.tabs.models.count, 2)
        XCTAssertEqual(regular.store.shownSpace?.tabs.models.count, 1)
        XCTAssertFalse(regular.pool.activePage?.wasOpenedAsPopup == true)
        XCTAssertTrue(
            privateContext.pool.activePage?.wasOpenedAsPopup == true
        )
    }

    // MARK: - Split View presented set

    func testRelockingASpaceHidesEveryCardOfAnOpenSplitWithoutUnloading() throws {
        let groupID = UUID()
        let first = TabState.Seed(
            title: "First secret",
            url: URL(string: "about:blank"),
            placement: .current,
            splitGroupID: groupID
        )
        let second = TabState.Seed(
            title: "Second secret",
            url: URL(string: "about:blank"),
            placement: .current,
            splitGroupID: groupID
        )
        let protectedSpace = makeSpace(
            tabs: [first, second],
            selectedTabID: first.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = TabState.Seed(title: "Open", url: nil, placement: .current)
        let openSpace = makeSpace(tabs: [openTab], selectedTabID: openTab.id)
        let browser = hosting(openSpace, protectedSpace)
        browser.unlockForTesting(protectedSpace)
        let pool = BrowserPagePool(browser: browser)

        present(pool, tab: openTab.id, in: openSpace.id)
        present(pool, tab: first.id, in: protectedSpace.id)
        XCTAssertEqual(pool.presentedTabIDs, [first.id, second.id])

        pool.relockProtectedSpace(try XCTUnwrap(pool.browser.spaceModel(protectedSpace.id)))

        XCTAssertTrue(
            pool.presentedTabIDs.isEmpty,
            "Locking a Space must take every card away, not just the focused one."
        )
        XCTAssertNil(pool.activeTabID)
        XCTAssertTrue(pool.containsResidentPage(for: first.id))
        XCTAssertTrue(pool.containsResidentPage(for: second.id))
        XCTAssertTrue(pool.containsResidentPage(for: openTab.id))
    }

    // MARK: - Archived tab state

    func testAFreshPoolOnTheSameArchiveRestoresWhatTheOldPoolLeft() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secondURL = try XCTUnwrap(URL(string: "https://state.crest.test/two"))
        let stateful = TabState.Seed(title: "Stateful", url: nil, placement: .current)
        let space = makeSpace(tabs: [stateful], selectedTabID: stateful.id)
        let firstBrowser = hosting(space)
        let firstLaunch = BrowserPagePool(
            browser: firstBrowser,
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        present(firstLaunch, tab: stateful.id, in: space.id)
        let page = try XCTUnwrap(firstLaunch.activePage)
        try await load(url, in: page)
        try await load(secondURL, in: page)
        // What a scene resigning active does, rather than an eviction.
        firstLaunch.archiveResidentTabStates()
        await firstLaunch.flushPendingTabStateWrites()
        let relaunched = try XCTUnwrap(firstBrowser.spaceModel(space.id)).value.seed
        firstLaunch.reconcile(validTabIDs: [])

        let secondLaunch = BrowserPagePool(
            browser: hosting(relaunched),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )
        present(secondLaunch, tab: stateful.id, in: space.id)
        let restoredPage = try XCTUnwrap(secondLaunch.activePage)

        XCTAssertEqual(restoredPage.webView.url, secondURL)
        XCTAssertEqual(
            restoredPage.webView.backForwardList.backList.map(\.url),
            [url]
        )

        secondLaunch.reconcile(validTabIDs: [])
    }

    func testPrivateBrowsingArchivesNoTabStateEvenWhenGivenAnArchive() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = TabState.Seed(title: "Private", url: nil, placement: .current)
        let other = TabState.Seed(title: "Other", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab, other], selectedTabID: tab.id)
        let pool = BrowserPagePool(
            browser: hosting(space),
            browsingMode: .privateBrowsing,
            tabStateArchive: archive
        )

        present(pool, tab: tab.id, in: space.id)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        present(pool, tab: other.id, in: space.id)
        pool.archiveResidentTabStates()
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(profileID: space.profileID, tabID: tab.id),
            "Private browsing must leave nothing on disk to restore."
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: archive.rootDirectory.path),
            "A private pool must not even create the archive's directory."
        )
    }

    func testDeletingASpaceRemovesItsArchivedTabStates() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let tab = TabState.Seed(title: "Deleted", url: nil, placement: .current)
        let space = makeSpace(tabs: [tab], selectedTabID: tab.id)
        let survivingProfileID = UUID()
        let survivingTabID = UUID()
        archive.archive(
            interactionState: Data("other space".utf8),
            url: url,
            history: nil,
            profileID: survivingProfileID,
            tabID: survivingTabID
        )
        let pool = BrowserPagePool(
            browser: hosting(space, on: .hostingPages(profileStores: RecordingWebsiteDataStoreRemover())),
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        present(pool, tab: tab.id, in: space.id)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.unloadPage(for: tab.id)
        await archive.flushPendingWrites()
        XCTAssertNotNil(
            archive.archivedState(profileID: space.profileID, tabID: tab.id)
        )

        try await pool.deleteData(for: BrowserSpaceRuntimeAssignment(space: space))
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(profileID: space.profileID, tabID: tab.id),
            "Deleting a Space must take its archived session state with it."
        )
        XCTAssertNotNil(
            archive.archivedState(
                profileID: survivingProfileID,
                tabID: survivingTabID
            ),
            "Space deletion must not reach another Space's state."
        )
    }

    func testRelockingAProtectedSpacePurgesTheStateItsUnloadsLeftBehind() async throws {
        let archive = try makeTabStateArchive()
        let url = try XCTUnwrap(URL(string: "https://state.crest.test/one"))
        let secret = TabState.Seed(title: "Secret", url: nil, placement: .current)
        let protectedSpace = makeSpace(
            tabs: [secret],
            selectedTabID: secret.id,
            accessPolicy: .deviceOwnerAuthentication
        )
        let openTab = TabState.Seed(title: "Open", url: nil, placement: .current)
        let openSpace = makeSpace(tabs: [openTab], selectedTabID: openTab.id)
        let browser = hosting(openSpace, protectedSpace)
        browser.unlockForTesting(protectedSpace)
        let pool = BrowserPagePool(
            browser: browser,
            usesEphemeralWebsiteDataStores: false,
            tabStateArchive: archive
        )

        present(pool, tab: openTab.id, in: openSpace.id)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        pool.unloadPage(for: openTab.id)
        present(pool, tab: secret.id, in: protectedSpace.id)
        try await load(url, in: try XCTUnwrap(pool.activePage))
        // The unload that leaves the residue: the page is gone from memory
        // long before the Space relocks, and its state is already on disk.
        pool.unloadPage(for: secret.id)
        await archive.flushPendingWrites()
        XCTAssertNotNil(
            archive.archivedState(
                profileID: protectedSpace.profileID,
                tabID: secret.id
            )
        )

        pool.relockProtectedSpace(try XCTUnwrap(pool.browser.spaceModel(protectedSpace.id)))
        await archive.flushPendingWrites()

        XCTAssertNil(
            archive.archivedState(
                profileID: protectedSpace.profileID,
                tabID: secret.id
            ),
            "A relocked Space must leave no page state at rest."
        )
        XCTAssertNotNil(
            archive.archivedState(
                profileID: openSpace.profileID,
                tabID: openTab.id
            ),
            "Relocking one Space must not reach another Space's state."
        )
    }

    /// Loads `url` as a simulated response so a back/forward entry exists without
    /// a network fixture, and waits for WebKit to commit it.
    private func load(_ url: URL, in page: BrowserPage) async throws {
        page.webView.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        page.webView.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: """
                <!doctype html><html><body style="height: 4000px">\(url.path)</body></html>
                """
        )
        for attempt in 0..<200 {
            if page.webView.url == url, !page.webView.isLoading {
                return
            }
            if attempt < 199 {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        XCTFail("Timed out loading \(url).")
    }

    private func makeTabStateArchive() throws -> BrowserTabStateArchive {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("crest-pool-tab-state-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return BrowserTabStateArchive(rootDirectory: root)
    }

    private func makePopupContext(
        browsingMode: BrowserBrowsingMode = .standard,
        tabStateArchive: (any BrowserTabStateArchiving)? = nil
    ) throws -> PopupAdoptionContext {
        let openerTab = TabState.Seed(title: "Opener", url: nil, placement: .current)
        let space = makeSpace(tabs: [openerTab], selectedTabID: openerTab.id)
        let store = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: fixtureSelections
        )
        let pool = BrowserPagePool(
            browser: store,
            browsingMode: browsingMode,
            usesEphemeralWebsiteDataStores: tabStateArchive == nil,
            tabStateArchive: tabStateArchive
        )
        pool.select()
        return PopupAdoptionContext(
            store: store,
            pool: pool,
            opener: try XCTUnwrap(pool.activePage)
        )
    }

    /// A window over a session holding `spaces`, showing the first with the
    /// tab each fixture Space shows, on `core` when another workspace of the
    /// test already hosts pages there.
    private func hosting(_ spaces: SpaceState.Seed..., on core: CrestCore = .hostingPages()) -> BrowserStore {
        .hostingPages(SessionState.Seed(spaces: spaces), showing: spaces.first?.id, tabs: fixtureSelections, core: core)
    }

    private func makeSpace(
        tabs: [TabState.Seed],
        selectedTabID: UUID,
        accessPolicy: SpaceAccessPolicy = .open
    ) -> SpaceState.Seed {
        showing(
            selectedTabID,
            in: SpaceState.Seed(name: "Test", symbol: "circle", accent: .indigo, tabs: tabs, accessPolicy: accessPolicy)
        )
    }

    /// Which tab each fixture Space shows. Selection is window state, so the
    /// fixtures keep it beside the session rather than inside it.
    private var fixtureSelections: [UUID: UUID] = [:]

    private func showing(_ tabID: UUID, in space: SpaceState.Seed) -> SpaceState.Seed {
        fixtureSelections[space.id] = tabID
        return space
    }

    /// Shows tab `tabID` of Space `spaceID` in `pool`'s window, then presents
    /// what the window shows.
    private func present(_ pool: BrowserPagePool, tab tabID: UUID, in spaceID: UUID, at time: Date = .now) {
        pool.browser.selectSpace(spaceID)
        pool.browser.selectTab(tabID)
        pool.select(at: time)
    }

    /// Shows Space `spaceID` in `pool`'s window on the tab the fixture names
    /// for it, then presents what the window shows.
    private func present(_ pool: BrowserPagePool, showing spaceID: UUID) {
        pool.browser.selectSpace(spaceID)
        if let tabID = fixtureSelections[spaceID] { pool.browser.selectTab(tabID) }
        pool.select()
    }

}

final class BrowserPageLifecyclePolicyTests: XCTestCase {
}

/// One opener page, its pool, and the store that owns their tabs, so popup tests
/// drive the real `WKUIDelegate` entry point instead of the pool's adoption API.
@MainActor
private struct PopupAdoptionContext {
    let store: BrowserStore
    let pool: BrowserPagePool
    let opener: BrowserPage

    /// Hands the opener a configuration copied from its own, which is what WebKit
    /// does before calling `createWebViewWith`.
    func requestPopup(url: URL?, navigationType: WKNavigationType) -> WKWebView? {
        try? opener.requestTestPopup(url: url, navigationType: navigationType)
    }
}

@MainActor
extension BrowserPage {
    /// Drives the real `WKUIDelegate` entry point with the configuration WebKit
    /// would copy from this opener.
    func requestTestPopup(
        url: URL?,
        navigationType: WKNavigationType
    ) throws -> WKWebView? {
        let configuration = try XCTUnwrap(
            webView.configuration.copy() as? WKWebViewConfiguration
        )
        return webView(
            webView,
            createWebViewWith: configuration,
            for: StubPopupNavigationAction(
                url: url,
                navigationType: navigationType
            ),
            windowFeatures: WKWindowFeatures()
        )
    }
}

/// WebKit never lets an app build a real `WKNavigationAction`, so popup tests
/// stand in for the one WebKit hands to `createWebViewWith`: no target frame and
/// a navigation type that selects the popup trigger under test.
final class StubPopupNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
    private let stubRequest: URLRequest
    private let stubNavigationType: WKNavigationType
    private let stubModifierFlags: NSEvent.ModifierFlags

    init(url: URL?, navigationType: WKNavigationType, modifierFlags: NSEvent.ModifierFlags = []) {
        // `window.open()` without a destination reaches WebKit as a request
        // without a URL, which a stub can only reproduce by clearing it.
        var request = URLRequest(url: URL(fileURLWithPath: "/"))
        request.url = url
        stubRequest = request
        stubNavigationType = navigationType
        stubModifierFlags = modifierFlags
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { stubNavigationType }
    override var targetFrame: WKFrameInfo? { nil }
    override var modifierFlags: NSEvent.ModifierFlags { stubModifierFlags }
    override var buttonNumber: Int { 0 }
    var browserSourceOrigin: SiteOrigin? { nil }
}

@MainActor
private final class RecordingWebsiteDataStoreRemover:
    BrowserEngineProfileRemoving
{
    private(set) var removedProfileIDs: [UUID] = []

    func removeProfile(_ profile: BrowsingProfile, ephemeral: Bool) async throws {
        removedProfileIDs.append(profile.id)
    }
}

private final class PagePoolAuthenticationChallengeSenderStub:
    NSObject,
    URLAuthenticationChallengeSender
{
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}

extension SpaceState.Seed {
}
