import XCTest

@testable import CrestMobile

@MainActor
final class MobileSavedLocationRestoreActionTests: XCTestCase {
    func testStaleSpaceSelectionCannotRestoreOrNavigateEitherPage() throws {
        let context = makeContext()
        let sourcePage = try XCTUnwrap(context.pages.activePage)
        let sourcePageURL = sourcePage.live.documentURL
        context.browser.selectSpace(context.destination.id)
        var activationCount = 0
        let action = MobileSavedLocationRestoreAction(
            browser: context.browser,
            pages: context.pages,
            selectTab: { _ in activationCount += 1 }
        )

        let restored = action.perform(context.assignment)

        XCTAssertFalse(restored)
        XCTAssertEqual(activationCount, 0)
        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?
                .tabs.models.first?.address,
            context.awayURL
        )
        XCTAssertEqual(sourcePage.live.documentURL, sourcePageURL)
    }

    func testExactAssignmentRestoresAndActivatesItsOwnPage() throws {
        let context = makeContext()
        let action = MobileSavedLocationRestoreAction(
            browser: context.browser,
            pages: context.pages,
            selectTab: { tabID in
                context.browser.selectTab(tabID)
                context.pages.select()
            }
        )

        let restored = action.perform(context.assignment)

        XCTAssertTrue(restored)
        XCTAssertEqual(
            context.browser.spaceModel(context.source.id)?
                .tabs.models.first?.address,
            context.savedURL
        )
        XCTAssertEqual(context.pages.activePage?.tabID, context.assignment.tabID)
        XCTAssertEqual(context.pages.activePage?.spaceID, context.assignment.spaceID)
        XCTAssertEqual(context.pages.activePage?.profileID, context.assignment.profileID)
    }

    private func makeContext() -> Context {
        let savedURL = URL(string: "about:blank#saved")!
        let awayURL = URL(string: "about:blank#away")!
        let tab = TabState.Seed(
            id: Self.uuid(3),
            title: "Saved",
            url: awayURL,
            savedURL: savedURL,
            placement: .saved
        )
        let source = SpaceState.Seed(
            id: Self.uuid(1),
            profileID: Self.uuid(2),
            name: "Source",
            symbol: "1.circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
        let destinationTab = TabState.Seed(
            id: Self.uuid(6),
            title: "Destination",
            url: URL(string: "about:blank#destination"),
            placement: .current
        )
        let destination = SpaceState.Seed(
            id: Self.uuid(4),
            profileID: Self.uuid(5),
            name: "Destination",
            symbol: "2.circle",
            accent: .teal,
            folders: [],
            tabs: [destinationTab]
        )
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [source, destination]),
            showing: source.id, tabs: [source.id: tab.id, destination.id: destinationTab.id],
            browsingMode: .privateBrowsing
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            usesEphemeralWebsiteDataStores: true
        )
        pages.select()
        return Context(
            browser: browser,
            pages: pages,
            source: source,
            destination: destination,
            assignment: BrowserTabRuntimeAssignment(
                tabID: tab.id,
                spaceID: source.id,
                profileID: source.profileID
            ),
            savedURL: savedURL,
            awayURL: awayURL
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x41, 0x56, 0x45, 0x44, 0x4C, 0x4F, 0x43,
                0x41, 0x54, 0x49, 0x4F, 0x4E, 0x00, 0x00, finalByte
            )
        )
    }

    private struct Context {
        let browser: BrowserStore
        let pages: MobileBrowserPageStore
        let source: SpaceState.Seed
        let destination: SpaceState.Seed
        let assignment: BrowserTabRuntimeAssignment
        let savedURL: URL
        let awayURL: URL
    }
}
