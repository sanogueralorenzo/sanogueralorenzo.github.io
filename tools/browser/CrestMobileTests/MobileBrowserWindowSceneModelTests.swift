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

    func testColdStartupLeavesTabsUnselectedRegardlessOfLegacyPreference() {
        for behavior in [
            StartupBehavior.showStartPage,
            .lastActiveTab,
        ] {
            let rootBrowser = BrowserStore.hostingPages(
                .preview
            )
            let registry = MobileBrowserPageStoreRegistry(
                primary: MobileBrowserPageStore(browser: rootBrowser)
            )
            let model = MobileBrowserWindowSceneModel(
                id: UUID(),
                rootBrowser: rootBrowser,
                permissionCenter: BrowserSitePermissionCenter(),
                pageStoreRegistry: registry,
                spaceAccess: BrowserSpaceAccessController(),
                tabStateArchive: nil,
                windowLayouts: BrowserWindowLayouts(defaults: nil),
                startupBehavior: behavior,
                monitorsMemoryPressure: false
            )

            XCTAssertFalse(model.navigation.compactShowsPage)
            XCTAssertNil(model.browser.shownTab)
            XCTAssertTrue(model.browser.spaceModels.allSatisfy { model.browser.selectedTabID(in: $0.id) == nil })
            XCTAssertEqual(
                model.browser.spaceModels.flatMap(\.tabs.models).map(\.id),
                rootBrowser.spaceModels.flatMap(\.tabs.models).map(\.id)
            )
            XCTAssertEqual(model.pages.residentPageCount, 0)
        }
    }

    func testSetupLoadsItsNativeRuntimeBeforeOpeningTheDefaultStartupBrowser() async throws {
        let rootBrowser = BrowserStore.hostingPages(.preview)
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(browser: rootBrowser, usesEphemeralWebsiteDataStores: true))
        let model = MobileBrowserWindowSceneModel(
            id: UUID(), rootBrowser: rootBrowser, permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: registry, spaceAccess: BrowserSpaceAccessController(), tabStateArchive: nil,
            windowLayouts: BrowserWindowLayouts(defaults: nil), startupBehavior: .showStartPage,
            monitorsMemoryPressure: false, usesEphemeralWebsiteDataStores: true)
        model.privateBrowser.openNewTab(url: try XCTUnwrap(URL(string: "https://private.example")))
        let privateSession = model.privateBrowser.sessionSeed
        try model.browser.core.send(StartSetup(workspaceID: model.browser.family.workspaceID, entry: .firstRun))
        let result = await BrowserSetupFinish.finish(browser: model.browser, spaceAccess: model.spaceAccess)
        guard let guide = (result as? BrowserSetupCompleted)?.guide else {
            return XCTFail("Setup did not create a guide")
        }
        XCTAssertTrue(model.presentGettingStartedAfterSetup(matching: guide))
        XCTAssertNotNil(model.pages.nativeTabs.runtime(matching: guide, content: .gettingStarted))
        XCTAssertTrue(model.navigation.compactShowsPage)
        XCTAssertEqual(model.browser.spaceModels.first?.id, guide.spaceID)
        XCTAssertNil(model.pages.activePage)
        XCTAssertEqual(model.privateBrowser.sessionSeed, privateSession)
        model.navigation.adapt(to: .compact)
        XCTAssertTrue(model.navigation.compactShowsPage)
        XCTAssertFalse(
            model.presentGettingStartedAfterSetup(
                matching:
                    BrowserTabRuntimeAssignment(tabID: guide.tabID, spaceID: guide.spaceID, profileID: UUID())))
    }

    /// A scene that closes takes its private workspace with it, once. Shown
    /// again, it browses privately in a new workspace, never in the closed one.
    func testAClosedSceneClosesItsPrivateWorkspaceAndOpensANewOneWhenShownAgain() throws {
        let rootBrowser = BrowserStore.hostingPages(.preview)
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(browser: rootBrowser, usesEphemeralWebsiteDataStores: true))
        let model = MobileBrowserWindowSceneModel(
            id: UUID(), rootBrowser: rootBrowser, permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: registry, spaceAccess: BrowserSpaceAccessController(), tabStateArchive: nil,
            windowLayouts: BrowserWindowLayouts(defaults: nil), startupBehavior: .lastActiveTab,
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
            spaceAccess: BrowserSpaceAccessController(),
            tabStateArchive: nil,
            windowLayouts: BrowserWindowLayouts(defaults: nil),
            startupBehavior: .lastActiveTab,
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
            name: "Windows", symbol: "globe", accent: .indigo,
            folders: [], tabs: [sharedTab, otherTab])
        let root = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]),
            showing: space.id, tabs: [space.id: sharedTab.id])
        let registry = MobileBrowserPageStoreRegistry(
            primary: MobileBrowserPageStore(browser: root, usesEphemeralWebsiteDataStores: true))
        let permissionCenter = BrowserSitePermissionCenter()
        let spaceAccess = BrowserSpaceAccessController()
        let windowLayouts = BrowserWindowLayouts(defaults: nil)
        func makeScene() -> MobileBrowserWindowSceneModel {
            MobileBrowserWindowSceneModel(
                id: UUID(), rootBrowser: root, permissionCenter: permissionCenter,
                pageStoreRegistry: registry, spaceAccess: spaceAccess, tabStateArchive: nil,
                windowLayouts: windowLayouts, startupBehavior: .lastActiveTab,
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
