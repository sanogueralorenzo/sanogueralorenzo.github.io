import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserStoreWorkspaceTests: XCTestCase {
    func testTemporaryWorkspaceCannotDeleteItsBorrowedProfile() async throws {
        let source = BrowserStore(seed: .preview)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(source.shownSpace))
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let deleter = WorkspaceDataDeleter()
        let before = source.sessionSeed

        do {
            try await temporary.deleteSpace(assignment.spaceID, dataDeleter: deleter)
            XCTFail("The workspace must not delete its borrowed profile")
        } catch {
            XCTAssertEqual(
                error as? Rejection,
                .borrowedProfileRequiresOwner(BorrowedProfileRequiresOwner(workspaceID: temporary.family.workspaceID)))
        }
        XCTAssertFalse(deleter.wasCalled)
        XCTAssertEqual(source.sessionSeed, before)
    }

}

@MainActor
private final class WorkspaceDataDeleter: BrowserSpaceDataDeleting {
    var wasCalled = false

    func deleteData(for space: BrowserSpaceRuntimeAssignment) async throws {
        wasCalled = true
    }
}
