import Foundation
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserColdStartTests: XCTestCase {
    func testSimulatorRejectsAContainerAbsentFromItsEntitlements() {
        #if targetEnvironment(simulator)
            XCTAssertFalse(
                CloudKitBrowserCloudSyncRemoteService.currentProcessContainsContainer(
                    "iCloud.invalid.crest-startup-test"))
        #endif
    }

    func testFloatingColdLaunchPreservesSplitMembershipAndWarmUserSelection() throws {
        var session = SessionState.Seed.preview
        let group = UUID()
        session.spaces[0].tabs[0].placement = .current
        session.spaces[0].tabs[1].placement = .current
        session.spaces[0].tabs[0].splitGroupID = group
        session.spaces[0].tabs[1].splitGroupID = group
        let root = BrowserStore.hostingPages(session)
        let id = UUID()
        let layouts = BrowserWindowLayouts(defaults: nil)
        layouts.save(BrowserWindowState(id: id, sidebarIsPresented: false))
        let model = MobileBrowserWindowSceneModel(
            id: id,
            rootBrowser: root,
            permissionCenter: BrowserSitePermissionCenter(),
            pageStoreRegistry: MobileBrowserPageStoreRegistry(primary: MobileBrowserPageStore(browser: root)),
            spaceAccess: BrowserSpaceAccessController(),
            tabStateArchive: nil,
            windowLayouts: layouts,
            startupBehavior: .lastActiveTab,
            monitorsMemoryPressure: false,
            usesEphemeralWebsiteDataStores: true
        )
        XCTAssertTrue(model.navigation.compactShowsPage)
        XCTAssertFalse(model.navigation.regularSidebarIsDocked)
        XCTAssertNil(model.browser.shownTab)
        XCTAssertEqual(model.browser.spaceModels[0].tabs.models.prefix(2).map(\.splitGroupID), [group, group])
        let choice = try XCTUnwrap(model.browser.shownSpace?.tabs.models.first?.id)
        model.browser.selectTab(choice)
        model.prepareForInactiveScene()
        model.prepareForBackgroundScene()
        model.activateWindow()
        XCTAssertEqual(model.browser.shownTab?.id, choice)
    }

}
