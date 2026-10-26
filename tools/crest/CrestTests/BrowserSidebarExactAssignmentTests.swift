import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSidebarExactAssignmentTests: XCTestCase {
    func testCapturedTabCloseRejectsAReplacementBrowsingProfile() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        replaceProfile(of: context.source, in: context.store)

        XCTAssertFalse(
            context.store.closeTab(
                context.sourceTab.id,
                matching: assignment
            )
        )
        XCTAssertTrue(
            try XCTUnwrap(context.store.spaceModel(context.source.id))
                .tabs.contains(context.sourceTab.id)
        )
    }

    private func makeContext(sourceIsProtected: Bool = false) -> (
        store: BrowserStore,
        source: SpaceState.Seed,
        destination: SpaceState.Seed,
        sourceTab: TabState.Seed
    ) {
        let sourceTab = TabState.Seed(
            id: fixedUUID(1),
            title: "Source tab",
            url: nil,
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let destinationTab = TabState.Seed.startPage(
            id: fixedUUID(2),
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let source = SpaceState.Seed(
            id: fixedUUID(3),
            profileID: fixedUUID(4),
            name: "Source",
            symbol: "1.circle",
            accent: .indigo,
            folders: [],
            tabs: [sourceTab],
            accessPolicy: sourceIsProtected
                ? .deviceOwnerAuthentication
                : .open
        )
        let destination = SpaceState.Seed(
            id: fixedUUID(5),
            profileID: fixedUUID(6),
            name: "Destination",
            symbol: "2.circle",
            accent: .rose,
            folders: [],
            tabs: [destinationTab]
        )
        let store = BrowserStore(seed: SessionState.Seed(spaces: [source, destination]), core: .hostingPages())
        return (store, source, destination, sourceTab)
    }

    private func replaceProfile(
        of space: SpaceState.Seed,
        in store: BrowserStore
    ) {
        store.replaceProfileForTesting(of: space.id, with: fixedUUID(7))
    }

    private func fixedUUID(_ suffix: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x2D,
                0x45, 0x58, 0x41, 0x43, 0x54, 0x00, 0x00, suffix
            )
        )
    }

}
