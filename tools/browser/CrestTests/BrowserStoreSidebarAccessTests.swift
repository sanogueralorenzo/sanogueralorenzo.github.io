import XCTest

@testable import Crest

@MainActor
final class BrowserStoreSidebarAccessTests: XCTestCase {
    func testLockedSelectedSpaceHidesItsActionsUntilExactProfileUnlock() async throws {
        let context = makeContext(sourceIsProtected: true)

        XCTAssertFalse(
            context.browser.showsSelectedSpaceActions(accessController: context.access)
        )
        let didUnlock = await context.access.unlock(try XCTUnwrap(context.browser.spaceModel(context.source.id)))
        XCTAssertTrue(didUnlock)
        XCTAssertTrue(
            context.browser.showsSelectedSpaceActions(accessController: context.access)
        )

        context.browser.replaceProfileForTesting(of: context.source.id, with: Self.uuid(9))
        XCTAssertFalse(
            context.browser.showsSelectedSpaceActions(accessController: context.access)
        )
    }

    func testDeletingSpaceIsExcludedFromPickerAndDropDestinations() {
        let context = makeContext()
        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.destination.id))
        defer { context.browser.family.finishDeletingSpace(context.destination.id) }

        XCTAssertEqual(
            context.browser.availableSpaces
                .map(\.id),
            [context.source.id]
        )
        XCTAssertNil(
            context.browser.unlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: context.destination), accessController: context.access)
        )
    }

    func testLockedDestinationRemainsVisibleButRejectsTabDrops() {
        let context = makeContext(destinationIsProtected: true)

        XCTAssertEqual(
            context.browser.availableSpaces
                .map(\.id),
            [context.source.id, context.destination.id]
        )
        XCTAssertNil(
            context.browser.unlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(space: context.destination), accessController: context.access)
        )
    }

    func testTabMoveDestinationsIncludeOnlyExactCurrentlyUnlockedAssignments() async throws {
        let context = makeContext(destinationIsProtected: true)
        let sourceAssignment = BrowserSpaceRuntimeAssignment(space: context.source)

        XCTAssertTrue(
            context.browser.availableTabMoveDestinationSpaces(from: sourceAssignment, accessController: context.access)
                .isEmpty
        )

        let didUnlockDestination = await context.access.unlock(
            try XCTUnwrap(context.browser.spaceModel(context.destination.id)))
        XCTAssertTrue(didUnlockDestination)
        XCTAssertEqual(
            context.browser.availableTabMoveDestinationSpaces(from: sourceAssignment, accessController: context.access)
                .map(\.id),
            [context.destination.id]
        )

        context.browser.replaceProfileForTesting(of: context.destination.id, with: Self.uuid(9))
        XCTAssertTrue(
            context.browser.availableTabMoveDestinationSpaces(from: sourceAssignment, accessController: context.access)
                .isEmpty
        )

        XCTAssertTrue(context.browser.family.beginDeletingSpace(context.destination.id))
        defer { context.browser.family.finishDeletingSpace(context.destination.id) }
        XCTAssertTrue(
            context.browser.availableTabMoveDestinationSpaces(from: sourceAssignment, accessController: context.access)
                .isEmpty
        )
    }

    private func makeContext(
        sourceIsProtected: Bool = false,
        destinationIsProtected: Bool = false
    ) -> Context {
        let source = makeSpace(
            id: 1,
            profileID: 2,
            name: "Source",
            isProtected: sourceIsProtected
        )
        let destination = makeSpace(
            id: 3,
            profileID: 4,
            name: "Destination",
            isProtected: destinationIsProtected
        )
        let browser = BrowserStore(seed: SessionState.Seed(spaces: [source, destination]))
        let access = BrowserSpaceAccessController(authenticator: AcceptingAuthenticator())
        browser.attachSpaceAccess(access)
        return Context(
            browser: browser,
            access: access,
            source: source,
            destination: destination
        )
    }

    private func makeSpace(
        id: UInt8,
        profileID: UInt8,
        name: String,
        isProtected: Bool
    ) -> SpaceState.Seed {
        SpaceState.Seed(
            id: Self.uuid(id),
            profileID: Self.uuid(profileID),
            name: name,
            symbol: "square.grid.2x2",
            accent: .indigo,
            folders: [],
            tabs: [],
            accessPolicy: isProtected ? .deviceOwnerAuthentication : .open
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x41,
                0x43, 0x43, 0x45, 0x53, 0x53, 0x00, 0x00, finalByte
            )
        )
    }

    private struct Context {
        let browser: BrowserStore
        let access: BrowserSpaceAccessController
        let source: SpaceState.Seed
        let destination: SpaceState.Seed
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
