import Foundation
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserWindowSceneModelTests: XCTestCase {
    /// iPadOS restores a window scene with the value an earlier build saved,
    /// `{"rawValue": UUID}`. It restores the same window, a bare identity
    /// reads too, and this build saves the spelling an earlier build restores.
    func testAWindowRequestKeepsTheStoredIdentitySpellingAndReadsABareOne() throws {
        let id = UUID()
        let earlier = Data(#"{"rawValue":"\#(id.uuidString)"}"#.utf8)
        let bare = Data(#""\#(id.uuidString)""#.utf8)

        XCTAssertEqual(try JSONDecoder().decode(MobileWindowRequest.self, from: earlier).id, id)
        XCTAssertEqual(try JSONDecoder().decode(MobileWindowRequest.self, from: bare).id, id)
        let stored = try JSONSerialization.jsonObject(with: JSONEncoder().encode(MobileWindowRequest(id: id)))
        XCTAssertEqual(stored as? [String: String], ["rawValue": id.uuidString])
    }

    func testColdStartupRestoresTheWindowsLastSpaceAndTab() async throws {
        var seed = SessionState.Seed.preview
        for index in seed.spaces.indices {
            for tab in seed.spaces[index].tabs.indices where seed.spaces[index].tabs[tab].url != nil {
                seed.spaces[index].tabs[tab].url = "about:blank"
            }
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        core.engines.register(
            WebKitEngineBinding(profileStores: WebKitBrowserWebsiteDataStoreRemover(), contentRuleLists: nil),
            isDefault: true)
        _ = try core.send(
            AdoptLegacySession(
                installed: LegacySession(core: nil, wholeGraph: nil, history: [], journal: nil), seed: seed))
        let favicons = InMemoryBrowserFaviconStore()
        let stored = try BrowserCoreSessionAuthority.openStored(in: core, favicons: favicons)
        let rootBrowser = BrowserStore.production(stored: stored, core: core, favicons: favicons)
        let id = UUID()
        let previous = rootBrowser.makeWindowStore(BrowserWindowOpening(id: id, saved: true))
        let space = try XCTUnwrap(previous.spaceModels.last)
        let tab = try XCTUnwrap(space.tabs.models.first { $0.url != nil })
        previous.selectSpace(space.id)
        previous.selectTab(tab.id)
        _ = try rootBrowser.core.send(CloseWindow(windowID: id))
        let registry = MobileBrowserPageStoreRegistry(primary: MobileBrowserPageStore(browser: rootBrowser))
        let model = MobileBrowserWindowSceneModel(
            id: id, rootBrowser: rootBrowser, permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: registry, tabStateArchive: nil,
            windowLayouts: BrowserWindowLayouts(defaults: nil), monitorsMemoryPressure: false,
            usesEphemeralWebsiteDataStores: true)
        XCTAssertEqual(model.browser.selectedSpaceID, space.id)
        XCTAssertEqual(model.browser.shownTab?.id, tab.id)
        XCTAssertTrue(model.navigation.compactShowsPage)
        XCTAssertEqual(model.pages.residentPageCount, 0)
        let rootModel = MobileBrowserRootModel(
            browser: model.browser, pages: model.pages, navigation: model.navigation,
            windowState: model.windowState, persistedSidebarWidth: MobileBrowserRootLayout.defaultRegularSidebarWidth)
        rootModel.presentationChanged(to: .compact)
        await rootModel.prepareBrowser()
        XCTAssertEqual(model.pages.activePage?.tabID, tab.id)
        XCTAssertTrue(model.navigation.compactShowsPage)
        await rootBrowser.flushPendingSyncPersistence()
    }

    /// A scene that closes takes its private workspace with it, once. Shown
    /// again, it browses privately in a new workspace, never in the closed one.
    func testAClosedSceneClosesItsPrivateWorkspaceAndOpensANewOneWhenShownAgain() throws {
        let rootBrowser = BrowserStore.hostingPages(.preview)
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(browser: rootBrowser, usesEphemeralWebsiteDataStores: true))
        let model = MobileBrowserWindowSceneModel(
            id: UUID(), rootBrowser: rootBrowser, permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: registry, tabStateArchive: nil,
            windowLayouts: BrowserWindowLayouts(defaults: nil),
            monitorsMemoryPressure: false, usesEphemeralWebsiteDataStores: true)
        let closing = model.privateBrowser
        let closed = closing.family.workspaceID

        model.closeWindowRuntime()
        model.closeWindowRuntime()

        XCTAssertFalse(closing.family.isOpen)
        XCTAssertNil(rootBrowser.core.state.workspaces[closed])
        model.activateWindow()
        XCTAssertFalse(model.privateBrowser === closing)
        XCTAssertTrue(model.privateBrowser.family.isOpen)
        XCTAssertNotEqual(model.privateBrowser.family.workspaceID, closed)
        let url = try XCTUnwrap(URL(string: "https://private.example"))
        let tab = try XCTUnwrap(model.privateBrowser.openNewTab(url: url))
        XCTAssertTrue(model.privateBrowser.openTabIDs.contains(tab))
    }

    func testIsolatedWindowModelUsesOnlyEphemeralWebsiteData() throws {
        let rootBrowser = BrowserStore.hostingPages(
            .preview
        )
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(
                browser: rootBrowser,
                usesEphemeralWebsiteDataStores: true
            )
        )
        let model = MobileBrowserWindowSceneModel(
            id: UUID(),
            rootBrowser: rootBrowser,
            permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: registry,
            tabStateArchive: nil,
            windowLayouts: BrowserWindowLayouts(defaults: nil),
            monitorsMemoryPressure: false,
            usesEphemeralWebsiteDataStores: true
        )

        let tabID = try XCTUnwrap(model.browser.shownSpace?.tabs.models.first?.id)
        model.browser.selectTab(tabID)
        model.pages.select()

        let store = try XCTUnwrap(
            model.pages.activePage?.webView.configuration.websiteDataStore
        )
        XCTAssertFalse(store.isPersistent)
        XCTAssertNil(store.identifier)
    }

    func testScenesShareBrowsingEditsButKeepSelectionPagesAndPrivateSessionsIndependent() throws {
        let url = try XCTUnwrap(URL(string: "about:blank"))
        let sharedTab = TabState.Seed(title: "Shared", url: url, placement: .current)
        let otherTab = TabState.Seed(title: "Other", url: url, placement: .current)
        let space = SpaceState.Seed(
            name: "Windows",
            folders: [], tabs: [sharedTab, otherTab])
        let root = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]),
            showing: space.id, tabs: [space.id: sharedTab.id])
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(browser: root, usesEphemeralWebsiteDataStores: true))
        let permissionCenter = BrowserSitePermissionCenter()
        let windowLayouts = BrowserWindowLayouts(defaults: nil)
        func makeScene() -> MobileBrowserWindowSceneModel {
            MobileBrowserWindowSceneModel(
                id: UUID(), rootBrowser: root, permissionCenter: permissionCenter,
                pageStoreRegistry: registry, tabStateArchive: nil,
                windowLayouts: windowLayouts,
                monitorsMemoryPressure: false, usesEphemeralWebsiteDataStores: true)
        }
        let first = makeScene()
        let second = makeScene()
        defer {
            first.pages.reconcile(validTabIDs: [])
            second.pages.reconcile(validTabIDs: [])
        }
        first.browser.selectTab(sharedTab.id)
        second.browser.selectTab(otherTab.id)

        first.browser.pinTab(sharedTab.id)

        XCTAssertTrue(first.browser.family === second.browser.family)
        XCTAssertEqual(second.browser.shownSpace?.pinnedTabs.map(\.id), [sharedTab.id])
        XCTAssertEqual(first.browser.shownTab?.id, sharedTab.id)
        XCTAssertEqual(second.browser.shownTab?.id, otherTab.id)

        first.pages.select()
        second.browser.selectTab(sharedTab.id)
        second.pages.select()
        let firstPage = try XCTUnwrap(first.pages.activePage)
        let secondPage = try XCTUnwrap(second.pages.activePage)
        XCTAssertFalse(first.pages === second.pages)
        XCTAssertFalse(firstPage === secondPage)
        XCTAssertFalse(firstPage.webView === secondPage.webView)
        XCTAssertEqual(firstPage.tabID, secondPage.tabID)
        XCTAssertEqual(firstPage.profileID, secondPage.profileID)
        XCTAssertFalse(firstPage.webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(secondPage.webView.configuration.websiteDataStore.isPersistent)
        first.pages.reconcile(validTabIDs: [])
        XCTAssertNil(first.pages.activePage)
        XCTAssertTrue(second.pages.activePage === secondPage)
        XCTAssertNotNil(second.browser.shownTab)

        XCTAssertFalse(first.privateBrowser.family === second.privateBrowser.family)
        XCTAssertFalse(first.privateBrowser.family === root.family)
        XCTAssertFalse(second.privateBrowser.family === root.family)
        let secondPrivateSession = second.privateBrowser.sessionSeed
        let normalSession = root.sessionSeed
        let privateTabID = try XCTUnwrap(first.privateBrowser.openNewTab(url: url))
        XCTAssertTrue(first.privateBrowser.openTabIDs.contains(privateTabID))
        XCTAssertEqual(second.privateBrowser.sessionSeed, secondPrivateSession)
        XCTAssertEqual(root.sessionSeed, normalSession)
    }
}
