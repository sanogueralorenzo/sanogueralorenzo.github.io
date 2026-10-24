import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserPageAssignmentTests: XCTestCase {
    func testCurrentSelectionRequiresACompletePresentedRuntime() throws {
        let browser = BrowserStore.hostingPages(.preview)
        let pool = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        XCTAssertFalse(pool.isPresentingSelection())

        pool.select()
        XCTAssertTrue(pool.isPresentingSelection())

        pool.deactivatePagePresentation()
        XCTAssertFalse(pool.isPresentingSelection())
        pool.reconcile(validTabIDs: [])
    }

    func testCurrentSelectionRejectsChangedSplitMembershipAndFocus() {
        let group = UUID()
        // Web pages, which the sidebar lists and the core shows as split cards.
        let blank = URL(string: "about:blank")
        let first = TabState.Seed(title: "First", url: blank, placement: .current, splitGroupID: group)
        let second = TabState.Seed(title: "Second", url: blank, placement: .current, splitGroupID: group)
        let space = SpaceState.Seed(name: "Split", symbol: "circle", accent: .indigo, tabs: [first, second])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: first.id])
        let pool = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        pool.select()
        XCTAssertTrue(pool.isPresentingSelection())

        browser.selectTab(second.id)
        XCTAssertFalse(pool.isPresentingSelection())
        browser.selectTab(first.id)
        XCTAssertTrue(pool.isPresentingSelection())
        XCTAssertTrue(browser.closeTab(second.id))
        XCTAssertFalse(pool.isPresentingSelection())
        pool.reconcile(validTabIDs: [])
    }

    func testActivePageMatchingRequiresTheExactTabSpaceAndProfileAssignment() throws {
        let browser = BrowserStore.hostingPages(.preview)
        let tab = try XCTUnwrap(browser.shownTab)
        let space = try XCTUnwrap(browser.shownSpace)
        let pool = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        pool.select()
        let page = try XCTUnwrap(pool.activePage)

        XCTAssertTrue(
            pool.activePage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: tab.id,
                    spaceID: space.id,
                    profileID: space.profileID
                )
            ) === page
        )
        XCTAssertNil(
            pool.activePage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: UUID(),
                    spaceID: space.id,
                    profileID: space.profileID
                )
            )
        )
        XCTAssertNil(
            pool.activePage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: tab.id,
                    spaceID: UUID(),
                    profileID: space.profileID
                )
            )
        )
        XCTAssertNil(
            pool.activePage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: tab.id,
                    spaceID: space.id,
                    profileID: UUID()
                )
            )
        )
    }

    /// A split card binds a page it did not select, so the same drift guard the
    /// focused path uses has to hold for every member — including the unfocused
    /// ones, which is the case `activePage(matching:)` cannot answer at all.
    func testPresentedPageMatchingGuardsEveryCardsSpaceAndProfile() throws {
        let groupID = UUID()
        let members = try (1...2).map { index in
            TabState.Seed(
                title: "Member \(index)",
                url: try XCTUnwrap(URL(string: "https://split.crest.test/\(index)")),
                placement: .current,
                splitGroupID: groupID
            )
        }
        let outsider = TabState.Seed(title: "Outsider", url: nil, placement: .current)
        let space = SpaceState.Seed(
            name: "Split",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: members + [outsider]
        )
        let pool = BrowserPagePool(
            browser: .hostingPages(SessionState.Seed(spaces: [space])), usesEphemeralWebsiteDataStores: true)
        pool.present(tab: members[0].id, in: space.id)

        for member in members {
            let assignment = BrowserTabRuntimeAssignment(
                tabID: member.id,
                spaceID: space.id,
                profileID: space.profileID
            )
            XCTAssertTrue(
                pool.presentedPage(matching: assignment)
                    === pool.presentedPage(for: member.id),
                "Every card resolves its own page, focused or not."
            )
            XCTAssertNil(
                pool.presentedPage(
                    matching: BrowserTabRuntimeAssignment(
                        tabID: member.id,
                        spaceID: UUID(),
                        profileID: space.profileID
                    )
                )
            )
            XCTAssertNil(
                pool.presentedPage(
                    matching: BrowserTabRuntimeAssignment(
                        tabID: member.id,
                        spaceID: space.id,
                        profileID: UUID()
                    )
                )
            )
        }
        XCTAssertNil(
            pool.presentedPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: outsider.id,
                    spaceID: space.id,
                    profileID: space.profileID
                )
            ),
            "A tab outside the presented group has no card to bind."
        )

        pool.reconcile(validTabIDs: [])
    }
}
