import XCTest

@testable import CrestMobile

@MainActor
final class MobileDurableTabCloseTests: XCTestCase {
    func testCommandsApplyClosePolicyToPinnedAndSavedTabsWithoutReloadingThem() throws {
        for placement: TabPlacement in [.pinned, .saved] {
            for policy in SavedTabClosePolicy.all {
                let context = try makeContext(placement: placement)
                defer { context.pages.reconcile(validTabIDs: []) }
                // The core puts the page away as the session's preferences say.
                let preferences = BrowserAppPreferenceStore()
                preferences.bind(to: context.browser, legacy: .unsaved)
                preferences.savedTabClosePolicy = policy
                context.pages.select()
                let commands = MobileBrowserCommandController(browser: context.browser, pages: context.pages)

                XCTAssertEqual(commands.dismissSelectedTab(), context.tab.id)

                let closed = try XCTUnwrap(context.browser.shownSpace?.tabs.models.first)
                XCTAssertEqual(closed.id, context.tab.id)
                XCTAssertEqual(closed.savedURL, context.tab.savedURL)
                XCTAssertEqual(closed.url, policy == .returnToSavedURL ? context.tab.savedURL : context.tab.url)
                XCTAssertNil(context.browser.shownTab)
                XCTAssertNil(context.pages.activePage)
                XCTAssertFalse(context.pages.containsResidentPage(for: context.tab.id))
                XCTAssertTrue(try XCTUnwrap(context.browser.shownSpace).archive.entries.isEmpty)
            }
        }
    }

    func testLockedSpaceCommandCannotResetOrCloseItsDurableTab() throws {
        let context = try makeContext(placement: .saved)
        defer { context.pages.reconcile(validTabIDs: []) }
        let space = try XCTUnwrap(context.browser.shownSpace)
        context.browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: space.id)
        let original = context.browser.sessionSeed
        let commands = MobileBrowserCommandController(browser: context.browser, pages: context.pages)
        XCTAssertNil(commands.dismissSelectedTab())
        XCTAssertEqual(context.browser.sessionSeed, original)
    }

    private func makeContext(placement: TabPlacement) throws -> Context {
        let tab = TabState.Seed(
            title: "Durable", url: try XCTUnwrap(URL(string: "about:blank#child")),
            savedURL: try XCTUnwrap(URL(string: "about:blank#root")), placement: placement
        )
        let space = SpaceState.Seed(
            name: "Test", symbol: "circle", accent: .indigo,
            folders: [], tabs: [tab]
        )
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]),
            showing: space.id, tabs: [space.id: tab.id]
        )
        return Context(
            browser: browser,
            pages: MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true), tab: tab
        )
    }

    private struct Context {
        let browser: BrowserStore
        let pages: MobileBrowserPageStore
        let tab: TabState.Seed
    }
}
