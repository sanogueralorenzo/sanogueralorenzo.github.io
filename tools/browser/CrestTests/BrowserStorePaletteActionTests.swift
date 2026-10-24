import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserStorePaletteActionTests: XCTestCase {
    func testEmptySelectionActionsRejectChangedSelectionSpaceProfileAndLock() throws {
        let source = makeSpace(index: 1)
        let target = try assignment(for: source)
        let other = makeSpace(index: 2)
        let browser = makeBrowser(spaces: [source, other], showing: source.id)
        var selectionCount = 0
        let actions = BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: source), browser: browser,
            accessController: BrowserSpaceAccessController(), didSelectTab: { selectionCount += 1 })
        XCTAssertTrue(actions.isAvailable)
        XCTAssertFalse(actions.selectTab(try assignment(for: other)))

        func assertUnavailable(line: UInt = #line) {
            let session = browser.sessionSeed
            let window = browser.window
            XCTAssertFalse(actions.isAvailable, line: line)
            XCTAssertFalse(actions.selectTab(target), line: line)
            XCTAssertFalse(actions.openURL(URL(string: "about:blank")!), line: line)
            XCTAssertEqual(browser.sessionSeed, session, line: line)
            XCTAssertEqual(browser.window, window, line: line)
        }

        // The window chose a tab in the source Space.
        browser.activateSessionTab(target.tabID, in: source.id)
        assertUnavailable()
        browser.clearPresentedTabSelection(in: source.id)
        XCTAssertTrue(actions.isAvailable)

        // The window moved to another Space.
        browser.selectPresentedSpace(other.id)
        assertUnavailable()
        browser.selectPresentedSpace(source.id)
        browser.clearPresentedTabSelection(in: source.id)
        XCTAssertTrue(actions.isAvailable)

        // Its profile was replaced.
        browser.replaceProfileForTesting(of: source.id, with: uuid(0xF0))
        assertUnavailable()
        // It has its profile back, but asks for authentication.
        browser.replaceProfileForTesting(of: source.id, with: source.profileID)
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: source.id)
        assertUnavailable()
        // It is gone.
        browser.removeSpaceForTesting(source.id)
        assertUnavailable()
        XCTAssertEqual(selectionCount, 0)
    }

    func testTargetRequiresCurrentSpaceAndRejectsReplacementOrLock() throws {
        let source = makeSpace(index: 1)
        let destination = makeSpace(index: 2)
        let sourceAssignment = try assignment(for: source)
        let browser = makeBrowser(
            spaces: [source, destination], showing: source.id, tabs: [source.id: sourceAssignment.tabID])
        let access = BrowserSpaceAccessController()
        let destinationAssignment = try assignment(for: destination)

        XCTAssertTrue(
            browser.isPaletteSourceAvailable(sourceAssignment, accessController: access)
        )
        XCTAssertNotNil(
            browser.paletteTarget(sourceAssignment, from: sourceAssignment, accessController: access)
        )
        XCTAssertNil(
            browser.paletteTarget(destinationAssignment, from: sourceAssignment, accessController: access)
        )

        browser.replaceProfileForTesting(of: source.id, with: uuid(0xF0))

        XCTAssertFalse(
            browser.isPaletteSourceAvailable(sourceAssignment, accessController: access)
        )
        XCTAssertNil(
            browser.paletteTarget(destinationAssignment, from: sourceAssignment, accessController: access)
        )

        browser.replaceProfileForTesting(of: source.id, with: source.profileID)
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: source.id)
        let protectedSource = try XCTUnwrap(browser.spaceModel(source.id)).value.seed
        XCTAssertNil(
            browser.paletteTarget(
                try assignment(for: protectedSource), from: sourceAssignment, accessController: access)
        )
    }

    private func makeBrowser(
        spaces: [SpaceState.Seed],
        showing spaceID: UUID,
        tabs: [UUID: UUID] = [:]
    ) -> BrowserStore {
        BrowserStore(seed: SessionState.Seed(spaces: spaces), showing: spaceID, tabs: tabs)
    }

    private func makeSpace(index: UInt8) -> SpaceState.Seed {
        let tab = TabState.Seed(
            id: uuid(index &+ 1),
            title: "Tab \(index)",
            url: URL(fileURLWithPath: "/palette-\(index)"),
            placement: .current
        )
        return SpaceState.Seed(
            id: uuid(index &+ 2),
            profileID: uuid(index &+ 3),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
    }

    private func assignment(
        for space: SpaceState.Seed
    ) throws -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: try XCTUnwrap(space.tabs.first?.id),
            spaceID: space.id,
            profileID: space.profileID
        )
    }

    private func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x50,
                0x41, 0x4C,
                0x45, 0x54,
                0x54, 0x45, 0x54, 0x45, 0x53, finalByte
            ))
    }
}
