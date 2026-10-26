import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCoreSessionAuthorityTests: XCTestCase {

    func testDeletionIntentSurvivesAdapterFailureAndRestartThenCommitsItsTombstoneWithTheSession() async throws {
        let target = SessionState.Seed.preview.spaces[0]
        let harness = try await BrowserStoredSessionHarness.staged(seed: .preview)
        let store = harness.store
        let other = store.makeWindowStore()
        let failing = DeletionAdapter(core: store.core) { space in
            // The intent is on disk before the engine erases anything.
            let intent = try XCTUnwrap(try harness.stored().session.spaceDeletions.first)
            XCTAssertEqual(intent.spaceID, space.spaceID)
            XCTAssertEqual(intent.profileID, space.profileID)
            XCTAssertTrue(other.deletingSpaceIDs.contains(space.spaceID))
            XCTAssertNotEqual(other.shownSpace?.id, space.spaceID)
            throw DeletionFailure.interrupted
        }
        do {
            try await store.deleteSpace(target.id, dataDeleter: failing)
            XCTFail("Expected adapter failure")
        } catch DeletionFailure.interrupted {}
        XCTAssertTrue(store.deletingSpaceIDs.contains(target.id))
        let saved = try harness.stored().session
        XCTAssertNotNil(saved.space(id: target.id))
        // The window's pages open through the core, which hosts them on WebKit
        // and refuses a page in a Space whose deletion is pending.
        harness.core.engines.register(WebKitEngineBinding(), isDefault: true)
        let pages = BrowserPagePool(browser: store)
        pages.select()
        XCTAssertNil(pages.activePage, "A restored window must not reopen a pending profile")
        let relaunched = try await harness.relaunch()
        let restarted = relaunched.store
        XCTAssertTrue(restarted.deletingSpaceIDs.contains(target.id))
        XCTAssertNotEqual(restarted.shownSpace?.id, target.id)
        let succeeding = DeletionAdapter(core: restarted.core) { space in
            XCTAssertEqual(space.profileID, target.profileID)
        }
        await restarted.resumePendingSpaceDeletions(dataDeleter: succeeding)
        XCTAssertEqual(succeeding.calls, [target.id])
        XCTAssertNil(restarted.spaceModel(target.id))
        XCTAssertEqual(restarted.workspaceModel?.spaceDeletions, [])
        XCTAssertEqual(try relaunched.stored().session, restarted.sessionSeed)
        XCTAssertTrue(try relaunched.storedJournalIsPublished())
        let targetRecords = try relaunched.storedJournal().records.filter { $0.spaceID == target.id }
        let tombstones = targetRecords.filter(\.isTombstone)
        XCTAssertFalse(tombstones.isEmpty)
        XCTAssertTrue(tombstones.allSatisfy { $0.deletionReason == .explicitDelete })
    }

    private enum DeletionFailure: Error { case interrupted }
    private final class DeletionAdapter: BrowserSpaceDataDeleting {
        var calls: [UUID] = []
        let core: CrestCore
        let action: (BrowserSpaceRuntimeAssignment) throws -> Void
        init(core: CrestCore, action: @escaping (BrowserSpaceRuntimeAssignment) throws -> Void) {
            self.core = core
            self.action = action
        }
        func deleteData(for space: BrowserSpaceRuntimeAssignment) async throws {
            calls.append(space.spaceID)
            try action(space)
            try await core.eraseProfile(of: space)
        }
    }

    /// Quitting and backgrounding wait for this flush and nothing after it:
    /// edits accepted just before are on disk and staged for sync once it
    /// returns, though a rename stages only after a coalescing delay and a new
    /// tab only once the turn that opened it ends.
    func testFlushLeavesTheLastEditsSavedAndStagedForSync() async throws {
        let harness = try await BrowserStoredSessionHarness.staged(seed: .preview)
        let store = harness.store
        let window = store.makeWindowStore(BrowserWindowOpening(saved: true))
        await store.flushPendingSyncPersistence()
        try harness.acknowledgePendingUploads()
        XCTAssertEqual(try harness.stored().journal?.pending.isEmpty, true)
        XCTAssertEqual(try harness.storedShownSpace(of: window.windowID), window.selectedSpaceID)

        let spaceID = try XCTUnwrap(store.spaceModels.first?.id)
        store.updateSpaceIdentity(spaceID, name: "Renamed before quit", symbol: "book", accent: .teal)
        let url = try XCTUnwrap(URL(string: "https://example.org/opened-before-quit"))
        let opened = try XCTUnwrap(store.openNewTab(url: url, in: spaceID, selecting: true))
        // Showing another Space changes only the window's record, never the session.
        let shown = try XCTUnwrap(store.spaceModels.first { $0.id != window.selectedSpaceID })
        window.selectPresentedSpace(shown.id)
        await store.flushPendingSyncPersistence()

        let stored = try harness.stored()
        XCTAssertEqual(stored.session.space(id: spaceID)?.settings.name, "Renamed before quit")
        XCTAssertEqual(stored.session.space(id: spaceID)?.contains(opened), true)
        let journal = try XCTUnwrap(stored.journal)
        XCTAssertTrue(journal.isPending(.space, spaceID))
        XCTAssertTrue(journal.isPending(.tab, opened))
        XCTAssertEqual(try harness.storedShownSpace(of: window.windowID), shown.id)
    }

    // MARK: - Fixtures
}
