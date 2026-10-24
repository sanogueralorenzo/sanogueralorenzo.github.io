import XCTest

@testable import CrestMobile

@MainActor
final class MobileGettingStartedTests: XCTestCase {
    func testMobileNativeRuntimeSurvivesSelectionAndUnloadsIndependentlyOfWebKit() async throws {
        let browser = BrowserStore.hostingPages()
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let id = try XCTUnwrap(browser.openGettingStarted())
        pages.select()
        let space = try XCTUnwrap(browser.shownSpace)
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profileID)
        let runtime = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertNil(pages.activePage)
        let state = runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }
        state.lesson = .folders
        browser.openNewTab()
        pages.select()
        XCTAssertNil(pages.prepareResidentPage(for: id))
        XCTAssertTrue(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted) === runtime)
        browser.selectTab(id)
        pages.select()
        XCTAssertEqual(state.lesson, .folders)
        pages.handleMemoryPressure(.critical)
        XCTAssertTrue(pages.nativeTabs.contains(assignment))
        XCTAssertFalse(
            pages.host.closeDurablePage(
                BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: UUID()), discardState: false))
        XCTAssertTrue(pages.unloadPage(for: id, matching: BrowserSpaceRuntimeAssignment(space: space)))
        XCTAssertFalse(pages.nativeTabs.contains(assignment))
        pages.select()
        let reopened = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertFalse(reopened === runtime)
        XCTAssertEqual(reopened.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }.lesson, .pin)
        await pages.releaseWindowRuntime(for: BrowserSpaceRuntimeAssignment(space: space))
        XCTAssertTrue(pages.nativeTabs.tabIDs.isEmpty)
    }

    func testSetupPresentsGuideBeforeBrowserWidthIsResolved() {
        let navigation = MobileBrowserNavigationState()
        navigation.adapt(to: .regular)
        navigation.presentSelectedTabAfterSetup()
        navigation.adapt(to: .compact)

        XCTAssertTrue(navigation.compactShowsPage)
        XCTAssertFalse(navigation.compactTabViewerChromeIsVisible)
        XCTAssertTrue(navigation.regularSidebarIsDocked)
        navigation.completePagePresentation()
        XCTAssertTrue(navigation.compactPageIsFullyPresented)
    }

}
