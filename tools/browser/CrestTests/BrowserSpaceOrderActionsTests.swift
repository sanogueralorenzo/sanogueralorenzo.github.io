import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSpaceOrderActionsTests: XCTestCase {
    func testMoveResolvesTheCurrentSpaceOrderAndPersistsWithoutChangingSpaceContents() throws {
        var session = SessionState.Seed.preview
        session.spaces.append(SpaceState.Seed.blank(number: session.spaces.count + 1))
        let originalSpaces = session.spaces
        let movedID = originalSpaces[0].id
        session.defaultSpaceID = originalSpaces[1].id
        let browser = BrowserStore(seed: session)
        let opened = browser.spaceModels.map(\.value)
        let shownSpaceID = browser.selectedSpaceID
        let actions = BrowserSpaceOrderActions(browser: browser, spaceID: movedID)
        XCTAssertFalse(actions.canMoveUp)
        XCTAssertTrue(actions.canMoveDown)

        browser.moveSpaces(from: IndexSet(integer: 0), to: session.spaces.count)
        actions.moveUp()

        XCTAssertEqual(browser.spaceModels.map(\.id), [originalSpaces[1].id, movedID, originalSpaces[2].id])
        XCTAssertEqual(browser.selectedSpaceID, shownSpaceID)
        XCTAssertEqual(browser.workspaceModel?.defaultSpaceID, session.defaultSpaceID)
        for original in opened {
            XCTAssertEqual(browser.spaceModel(original.id)?.value, original)
        }

        actions.moveDown()
        XCTAssertEqual(browser.spaceModels.last?.id, movedID)
        XCTAssertFalse(actions.canMoveDown)
        let revision = browser.sessionRevision
        actions.moveDown()
        let missing = BrowserSpaceOrderActions(browser: browser, spaceID: UUID())
        XCTAssertFalse(missing.canMoveUp)
        XCTAssertFalse(missing.canMoveDown)
        missing.moveUp()
        missing.moveDown()
        XCTAssertEqual(browser.sessionRevision, revision, "A move that cannot happen changes nothing")
    }
}
