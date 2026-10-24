import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserPagePresentationTests: XCTestCase {
    func testCompactPageActionsExposeOnlyTheSelectedRuntimeAssignment() throws {
        let firstTab = TabState.Seed(
            title: "First",
            url: URL(string: "about:blank"),
            placement: .current
        )
        let secondTab = TabState.Seed(
            title: "Second",
            url: URL(string: "about:blank"),
            placement: .current
        )
        let firstSpace = SpaceState.Seed(
            name: "First Space",
            symbol: "1.circle",
            accent: .indigo,
            folders: [],
            tabs: [firstTab]
        )
        let secondSpace = SpaceState.Seed(
            name: "Second Space",
            symbol: "2.circle",
            accent: .teal,
            folders: [],
            tabs: [secondTab]
        )
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [firstSpace, secondSpace]),
            showing: firstSpace.id, tabs: [firstSpace.id: firstTab.id, secondSpace.id: secondTab.id]
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            usesEphemeralWebsiteDataStores: true
        )
        pages.select()
        let firstPage = try XCTUnwrap(pages.activePage)
        let firstPort = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            spaceAccess: BrowserSpaceAccessController(),
            expectedAssignment: assignment(tab: firstTab, space: firstSpace)
        )

        XCTAssertTrue(firstPort.isAvailable)
        XCTAssertTrue(firstPort.activePage === firstPage)
        XCTAssertEqual(firstPort.activeURL, firstTab.address)

        browser.selectSpace(secondSpace.id)
        let secondPort = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            spaceAccess: BrowserSpaceAccessController(),
            expectedAssignment: assignment(tab: secondTab, space: secondSpace)
        )

        XCTAssertFalse(firstPort.isAvailable)
        XCTAssertNil(firstPort.pageAssignment)
        XCTAssertNil(firstPort.activePage)
        XCTAssertNil(firstPort.activeURL)
        XCTAssertFalse(firstPort.canGoBack)
        XCTAssertFalse(firstPort.canGoForward)
        XCTAssertTrue(firstPort.backHistory.isEmpty)
        XCTAssertTrue(firstPort.forwardHistory.isEmpty)
        XCTAssertFalse(firstPort.copyPageLink())
        firstPort.presentFind()
        XCTAssertTrue(pages.activePage === firstPage)
        XCTAssertFalse(firstPage.isFindPresented)

        XCTAssertFalse(secondPort.isAvailable)
        XCTAssertNil(secondPort.activePage)
        XCTAssertNil(secondPort.activeURL)
        XCTAssertFalse(secondPort.copyPageLinkAsMarkdown())

        pages.select()
        let secondPage = try XCTUnwrap(pages.activePage)
        XCTAssertTrue(secondPort.isAvailable)
        XCTAssertTrue(secondPort.activePage === secondPage)
        secondPort.presentFind()
        XCTAssertTrue(secondPage.isFindPresented)
        XCTAssertFalse(firstPage.isFindPresented)

        let wrongProfilePort = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            spaceAccess: BrowserSpaceAccessController(),
            expectedAssignment: BrowserTabRuntimeAssignment(
                tabID: secondTab.id,
                spaceID: secondSpace.id,
                profileID: UUID()
            )
        )
        XCTAssertFalse(wrongProfilePort.isAvailable)
        XCTAssertNil(wrongProfilePort.activePage)
    }

    private func assignment(
        tab: TabState.Seed,
        space: SpaceState.Seed
    ) -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: tab.id,
            spaceID: space.id,
            profileID: space.profileID
        )
    }
}
