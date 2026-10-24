import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSplitGroupSessionTests: XCTestCase {
    private let mutationDate = Date(timeIntervalSince1970: 1_000)

    // MARK: - Reordering cards inside a run

    // MARK: - "Split with Current Tab" and "Open Link in Split View"

    func testSplitGroupCustomizationPersistsEveryFieldAndFullEmojiCluster()
        throws
    {
        let group = UUID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail])
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = makeStore(space: space, selectedTabID: head.id)
        let tint = BrandColor(red: 0.16, green: 0.48, blue: 0.82)
        let emoji = "👨🏽‍💻"

        XCTAssertTrue(store.setSplitGroupTitle("  Research Pair  ", groupID: group, matching: assignment))
        XCTAssertTrue(store.setSplitGroupEmojiIcon(emoji, groupID: group, matching: assignment))
        XCTAssertTrue(store.setSplitGroupTint(tint, groupID: group, matching: assignment))

        // What another window opens from the session as it holds it now.
        let reopened = BrowserStore(seed: store.sessionSeed)
        let metadata = try XCTUnwrap(
            reopened.spaceModel(space.id)?.splitGroups.first(where: { $0.id == group })
        )
        XCTAssertEqual(metadata.customTitle, "Research Pair")
        XCTAssertEqual(metadata.customIconSymbol.flatMap(BrowserIconSymbol.emoji(from:)), emoji)
        XCTAssertEqual(metadata.tint, tint)
        XCTAssertNotNil(metadata.titleModifiedAt)
        XCTAssertNotNil(metadata.iconModifiedAt)
        XCTAssertNotNil(metadata.tintModifiedAt)
    }

    func testDissolvingAGroupRemovesItsDurableCustomization() throws {
        let group = UUID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail])
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let store = makeStore(space: space, selectedTabID: head.id)
        XCTAssertTrue(store.setSplitGroupTitle("Temporary Pair", groupID: group, matching: assignment))

        XCTAssertTrue(store.removeTabFromSplit(tail.id, matching: assignment))

        let repaired = try XCTUnwrap(store.spaceModel(space.id))
        XCTAssertNil(repaired.splitGroups.first(where: { $0.id == group }))
        XCTAssertTrue(repaired.splitGroups.isEmpty)
    }

    func testRepairRetainsMetadataWhileOnlyOneSyncedMemberHasArrived() throws {
        let group = UUID()
        let lone = makeTab("First Arrival", group: group)
        let metadata = SplitGroupState.Seed(id: group, customTitle: "Synced Pair", titleModifiedAt: mutationDate)
        let space = SpaceState.Seed(
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [lone],
            splitGroups: [metadata]
        )

        let store = makeStore(space: space, selectedTabID: lone.id)

        XCTAssertEqual(
            try XCTUnwrap(store.spaceModel(space.id)).splitGroups.map(\.seed),
            [metadata],
            "Runtime repair cannot erase metadata before the remaining CloudKit tab records arrive."
        )
    }

    private func makeStore(
        folders: [FolderState.Seed] = [],
        tabs: [TabState.Seed],
        selectedTabID: UUID?
    ) -> BrowserStore {
        makeStore(space: makeSpace(folders: folders, tabs: tabs), selectedTabID: selectedTabID)
    }

    /// A window showing `space` on `selectedTabID`.
    private func makeStore(space: SpaceState.Seed, selectedTabID: UUID?) -> BrowserStore {
        BrowserStore(
            seed: SessionState.Seed(spaces: [space]),
            showing: space.id, tabs: selectedTabID.map { [space.id: $0] } ?? [:]
        )
    }

    private func makeSpace(
        name: String = "Work",
        folders: [FolderState.Seed] = [],
        tabs: [TabState.Seed]
    ) -> SpaceState.Seed {
        SpaceState.Seed(
            name: name,
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: folders,
            tabs: tabs
        )
    }

    private func makeTab(
        _ title: String,
        placement: TabPlacement = .current,
        folderID: UUID? = nil,
        group: UUID? = nil
    ) -> TabState.Seed {
        TabState.Seed(
            title: title,
            url: URL(string: "https://example.com/\(title.replacingOccurrences(of: " ", with: "-"))"),
            placement: placement,
            folderID: folderID,
            splitGroupID: group,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
