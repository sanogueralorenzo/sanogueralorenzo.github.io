import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSplitTabCopyTests: XCTestCase {

    func testInvalidDurableSplitLeavesSessionAndPersistenceUntouched() throws {
        let source = tab("Source", placement: .saved)
        let target = tab("Target", placement: .pinned)
        let store = store(tabs: [source, target], selected: target.id)
        let space = try XCTUnwrap(store.shownSpace)
        let original = store.sessionSeed
        let item = BrowserTabDragItem(tabID: source.id, spaceID: space.id, profileID: space.profileID)
        XCTAssertFalse(store.addTabToSplit(item, joining: source.id, at: nil))
        XCTAssertFalse(store.addTabToSplit(item, joining: UUID(), at: nil))
        XCTAssertFalse(
            store.addTabToSplit(
                BrowserTabDragItem(tabID: source.id, spaceID: space.id, profileID: UUID()),
                joining: target.id, at: nil
            ))
        XCTAssertEqual(store.sessionSeed, original)
    }

    func testSavedDestinationGroupIsCopiedInOrderAndSurvivesSessionReload() throws {
        let folder = FolderState.Seed(title: "Nested research")
        let groupID = UUID()
        var head = tab("Head", placement: .saved, folder: folder.id)
        var tail = tab("Tail", placement: .saved, folder: folder.id)
        head.splitGroupID = groupID
        tail.splitGroupID = groupID
        let source = tab("Pinned", placement: .pinned)
        let store = store(tabs: [source, head, tail], folders: [folder], selected: tail.id)
        let space = try XCTUnwrap(store.shownSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        XCTAssertTrue(store.setSplitGroupTitle("Research pair", groupID: groupID, matching: assignment))
        let originals = try XCTUnwrap(store.shownSpace)
        let originalDurableTabs = originals.tabs.values.map(\.seed)

        XCTAssertTrue(
            store.addTabToSplit(
                BrowserTabDragItem(tabID: source.id, spaceID: space.id, profileID: space.profileID),
                joining: tail.id, at: 1
            ))

        let copiedGroup = try XCTUnwrap(
            store.shownSpace?.shownSplit(containing: try XCTUnwrap(store.shownTab).id))
        XCTAssertNotEqual(copiedGroup, groupID)
        XCTAssertEqual(
            store.shownSpace?.splitMembers(of: copiedGroup).map(\.title), ["Head", "Pinned", "Tail"])
        XCTAssertEqual(
            store.shownSpace?.splitGroups.first(where: { $0.id == copiedGroup })?.customTitle, "Research pair")
        // What another window opens from the session as it holds it now.
        let restoredSpace = BrowserStore(seed: store.sessionSeed).spaceModel(space.id)
        XCTAssertEqual(
            restoredSpace?.splitMembers(of: copiedGroup).map(\.id),
            store.shownSpace?.splitMembers(of: copiedGroup).map(\.id))
        XCTAssertEqual(
            restoredSpace?.tabs.values.filter { $0.placement != .current }.map(\.seed), originalDurableTabs)
        XCTAssertEqual(
            restoredSpace?.splitGroups.first(where: { $0.id == groupID }),
            originals.splitGroups.first(where: { $0.id == groupID }))
    }

    func testSyncRoundTripKeepsDurableOriginalsAndOpenFolderMembership() async throws {
        let savedFolder = FolderState.Seed(title: "Saved research")
        let currentFolder = FolderState.Seed(title: "Open work", location: .current)
        let source = tab("Saved", placement: .saved, folder: savedFolder.id)
        var target = tab("Open", placement: .current)
        target.folderID = currentFolder.id
        let space = SpaceState.Seed(
            name: "Work", symbol: "globe", accent: .teal,
            folders: [savedFolder, currentFolder], tabs: [source, target])
        let harness = try await BrowserStoredSessionHarness.uploaded(seed: SessionState.Seed(spaces: [space]))
        let store = harness.store
        store.selectTab(target.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(store.shownSpace))
        XCTAssertTrue(store.splitTabWithSelectedTab(source.id, matching: assignment))
        let copy = try XCTUnwrap(store.shownTab)
        XCTAssertEqual(copy.folderID, currentFolder.id)
        let pending = try await harness.pendingRecords()
        // Another device that takes everything this one holds from the cloud.
        let materialized = try await harness.joiningDevice().store
        let restored = try XCTUnwrap(materialized.spaceModel(store.selectedSpaceID))
        XCTAssertEqual(restored.tabs.models.map(\.id), store.shownSpace?.tabs.models.map(\.id))
        XCTAssertEqual(restored.tabs.model(source.id)?.folderID, savedFolder.id)
        XCTAssertEqual(restored.tabs.model(source.id)?.savedURL, source.savedURL)
        XCTAssertEqual(restored.tabs.model(copy.id)?.folderID, currentFolder.id)
        XCTAssertEqual(restored.tabs.model(copy.id)?.splitGroupID, copy.splitGroupID)
        XCTAssertFalse(pending.contains { $0.kind == .tab && $0.id == source.id })
    }

    private func tab(_ title: String, placement: TabPlacement, folder: UUID? = nil) -> TabState.Seed {
        TabState.Seed(
            title: title,
            url: URL(string: "https://crest.test/\(title)/child"),
            savedURL: placement == .current ? nil : URL(string: "https://crest.test/\(title)"),
            iconMode: .automatic,
            placement: placement,
            folderID: placement == .saved ? folder : nil
        )
    }

    private func store(tabs: [TabState.Seed], folders: [FolderState.Seed] = [], selected: UUID) -> BrowserStore {
        let space = SpaceState.Seed(
            name: "Work", symbol: "globe", accent: .teal, folders: folders,
            tabs: tabs)
        return BrowserStore(
            seed: SessionState.Seed(spaces: [space]),
            showing: space.id, tabs: [space.id: selected])
    }
}
