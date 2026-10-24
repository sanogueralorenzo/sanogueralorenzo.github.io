import CloudKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserGettingStartedTests: XCTestCase {
    func testNativeStateSurvivesSelectionAndEndsAtExplicitUnload() throws {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let id = try XCTUnwrap(browser.openGettingStarted())
        pages.select()
        let space = try XCTUnwrap(browser.shownSpace)
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profileID)
        let runtime = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        let state = runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }
        state.chapter = .splitView
        state.practice.makeSplit()
        let members = state.practice.members.map(\.id)
        browser.openNewTab()
        pages.select()
        browser.selectTab(id)
        pages.select()
        XCTAssertTrue(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted) === runtime)
        XCTAssertEqual(state.chapter, .splitView)
        XCTAssertEqual(state.practice.members.map(\.id), members)
        XCTAssertFalse(
            pages.host.closeDurablePage(
                BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: UUID()), discardState: false))
        XCTAssertTrue(pages.nativeTabs.contains(assignment))
        XCTAssertTrue(
            BrowserDurableTabCloseAction(browser: browser, spaceAccess: BrowserSpaceAccessController()).perform(
                assignment))
        XCTAssertTrue(browser.shownSpace?.tabs.contains(id) == true)
        XCTAssertNil(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        browser.selectTab(id)
        pages.select()
        let reopened = try XCTUnwrap(pages.nativeTabs.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertFalse(reopened === runtime)
        XCTAssertEqual(reopened.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }.chapter, .tabs)
    }

    func testNativeStateIsScopedToWindowAssignmentAndDescriptor() throws {
        let browser = BrowserStore.preview()
        let id = try XCTUnwrap(browser.openGettingStarted())
        let space = try XCTUnwrap(browser.shownSpace)
        let tab = try XCTUnwrap(browser.shownTab)
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profileID)
        let first = BrowserNativeTabStore()
        let second = BrowserNativeTabStore()
        first.load(tab: tab, space: space)
        second.load(tab: tab, space: space)
        let runtime = try XCTUnwrap(first.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertFalse(second.runtime(matching: assignment, content: .gettingStarted) === runtime)
        let stale = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: UUID())
        XCTAssertFalse(first.remove(tabID: id, matching: stale))
        // The same tab showing Settings in the same Space.
        var seed = space.value.seed
        let settings = TabState.Seed(
            id: id, title: "Settings", url: nil, nativeContent: .settings, placement: .saved)
        seed.tabs = [settings]
        let settingsSpace = SpaceModel.detached(seed)
        let settingsTab = try XCTUnwrap(settingsSpace.tabs.model(id))
        first.load(tab: settingsTab, space: settingsSpace)
        XCTAssertNil(first.runtime(matching: assignment, content: .gettingStarted))
        XCTAssertNotNil(first.runtime(matching: assignment, content: .settings))
        // The same Space and tab under another profile.
        seed.profileID = UUID()
        let replacement = SpaceModel.detached(seed)
        first.reconcile(spaces: [replacement])
        XCTAssertTrue(first.tabIDs.isEmpty)
        first.load(tab: try XCTUnwrap(replacement.tabs.model(id)), space: replacement)
        first.reconcile(validTabIDs: [])
        XCTAssertTrue(first.tabIDs.isEmpty)
    }

    func testNativePressurePreservesPresentedCardsAndWindowTeardownReleasesState() async throws {
        let browser = BrowserStore.hostingPages()
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let guide = try XCTUnwrap(browser.openGettingStarted())
        pages.select()
        let settings = try XCTUnwrap(browser.openSettings())
        pages.select()
        pages.relieveMemoryPressure(.critical)
        XCTAssertFalse(pages.nativeTabs.tabIDs.contains(guide))
        XCTAssertTrue(pages.nativeTabs.tabIDs.contains(settings))
        await pages.releaseWindowRuntime(for: BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(browser.shownSpace)))
        XCTAssertTrue(pages.nativeTabs.tabIDs.isEmpty)
    }

    func testNativeGuideReusesItsTabAndNeverAllocatesWebKit() throws {
        let browser = BrowserStore.hostingPages()
        let first = try XCTUnwrap(browser.openGettingStarted())
        XCTAssertEqual(browser.openGettingStarted(), first)
        XCTAssertEqual(browser.shownSpace?.tabs.models.filter { $0.nativeTabContent == .gettingStarted }.count, 1)
        XCTAssertNil(browser.shownTab?.address)
        XCTAssertFalse(try XCTUnwrap(browser.shownTab).isStartPage)
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        pages.select()
        XCTAssertEqual(pages.activeTabID, first)
        XCTAssertEqual(pages.presentedTabIDs, [first])
        XCTAssertNil(pages.activePage)
        XCTAssertFalse(pages.retainedTabIDs.contains(first))
        XCTAssertFalse(pages.retainedTabIDs.contains(first))
        pages.selectSpace(in: browser)
        XCTAssertEqual(browser.shownTab?.id, first)
    }

    func testNativeActionsRejectAStaleProfileAndKeepGuideWhenOpeningALink() throws {
        let browser = BrowserStore.preview()
        let id = try XCTUnwrap(browser.openGettingStarted())
        let space = try XCTUnwrap(browser.shownSpace)
        var opened = 0
        let actions = BrowserNativeTabActions(
            browser: browser, spaceAccess: BrowserSpaceAccessController(), didOpenURL: { opened += 1 })
        let url = URL(string: "https://example.com")!
        actions.openURL(
            BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: UUID()), .gettingStarted, url)
        XCTAssertEqual(opened, 0)
        actions.openURL(
            BrowserTabRuntimeAssignment(tabID: id, spaceID: space.id, profileID: space.profileID), .gettingStarted, url
        )
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(browser.shownTab?.address, url)
        XCTAssertEqual(browser.shownSpace?.tabs.model(id)?.nativeTabContent, .gettingStarted)
    }

}
