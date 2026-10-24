import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCurrentTabFolderTests: XCTestCase {

    func testNestedCurrentFoldersSyncToAnotherDeviceWithMetadataAndMembership() async throws {
        let root = FolderState.Seed(
            title: "Research", location: .current, color: BrandColor.ocean, isCollapsed: true,
            collapseModifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let nested = FolderState.Seed(
            title: "Nested", location: .current, color: BrandColor.rose, parentID: root.id)
        let child = nested.id
        let browser = makeBrowser { space in
            space.folders = [root, nested]
            space.tabs[1].folderID = child
        }
        let space = try XCTUnwrap(browser.shownSpace)
        let firstCurrent = try XCTUnwrap(space.currentTabs.first?.id)
        let remote = try await BrowserStoredSessionHarness.staged(seed: browser.sessionSeed).joiningDevice().store
        let restored = try XCTUnwrap(remote.spaceModel(space.id))
        XCTAssertEqual(restored.folders.values, space.folders.values)
        XCTAssertEqual(restored.tabs.model(firstCurrent)?.folderID, child)
        XCTAssertEqual(restored.tabs.model(firstCurrent)?.placement, .current)
    }

    func testSyncPreferencesIncludeEachFolderWithItsSectionAndPreserveDisabledLocalSections() async throws {
        let browser = makeBrowser()
        let space = try XCTUnwrap(browser.shownSpace)
        let firstCurrent = try XCTUnwrap(space.currentTabs.first?.id)
        let saved = try XCTUnwrap(browser.addFolder(title: "Saved", in: space.id))
        let current = try XCTUnwrap(browser.createTabFolder([firstCurrent], in: space.id))
        // A device that does not sync its current tabs.
        let device = try BrowserStoredSessionHarness(
            seed: browser.sessionSeed,
            journalData: StoredSyncJournal.fresh(deviceID: UUID(), syncsCurrentTabs: false))
        let records = try await device.heldRecords()
        XCTAssertEqual(records.filter { $0.kind == .folder }.map(\.id), [saved])
        try device.deliverNow(MergeSyncRecords(records: records))
        let refreshed = try XCTUnwrap(device.store.spaceModel(space.id))
        XCTAssertEqual(refreshed.folders.model(current)?.location, .current)
        XCTAssertEqual(refreshed.tabs.model(firstCurrent)?.folderID, current)
    }

    /// One saved tab followed by four open tabs, showing the last one.
    private func makeBrowser(_ configure: (inout SpaceState.Seed) -> Void = { _ in }) -> BrowserStore {
        var space = SpaceState.Seed.blank(number: 1)
        space.tabs = (0..<5).map { i in
            TabState.Seed(
                id: UUID(), title: "Tab \(i)", url: URL(string: "https://example.com/\(i)"),
                symbol: "globe", placement: i == 0 ? .saved : .current)
        }
        configure(&space)
        return makeStore(space, showing: space.tabs[4].id)
    }

    /// A window showing `tabID` in the only Space.
    private func makeStore(_ space: SpaceState.Seed, showing tabID: UUID) -> BrowserStore {
        BrowserStore(
            seed: SessionState.Seed(spaces: [space]),
            showing: space.id, tabs: [space.id: tabID])
    }
}
