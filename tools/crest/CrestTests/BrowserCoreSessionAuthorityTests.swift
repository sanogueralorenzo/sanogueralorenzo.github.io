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

    /// A merge the transport sends from its own thread is on disk with its
    /// journal when it returns, and reaches every window through the wake and
    /// one drain.
    func testIncomingSyncPublishesAndPersistsTheSameSessionAcrossWindows() async throws {
        let space = SessionState.Seed.preview.spaces[0]
        let harness = try await BrowserStoredSessionHarness.staged(seed: .preview)
        let store = harness.store
        let other = store.makeWindowStore()
        // Another device that holds the same records renames the Space.
        let remote = try await harness.joiningDevice()
        remote.store.updateSpaceIdentity(
            space.id, name: "Remote Space")
        let core = harness.core
        let merge = MergeSyncRecords(records: try await remote.pendingRecords())
        try await Task.detached { _ = try core.deliver(merge) }.value
        // The merge and its journal are on disk when the merge returns.
        XCTAssertEqual(try harness.stored().session.spaces[0].settings.name, "Remote Space")
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertEqual(store.spaceModels.first?.settings.name, "Remote Space")
        XCTAssertEqual(other.spaceModels.first?.settings.name, "Remote Space")
        XCTAssertEqual(try harness.stored().session, store.sessionSeed)
        XCTAssertTrue(try harness.storedJournalIsPublished())
        // A local edit is saved behind; staging it and the flush a window
        // waits for put both on disk.
        store.updateSpaceIdentity(space.id, name: "Local after sync")
        await store.flushPendingSyncPersistence()
        let restored = try harness.stored()
        XCTAssertEqual(restored.session.spaces[0].settings.name, "Local after sync")
        XCTAssertTrue(try harness.storedJournalIsPublished())
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
        store.updateSpaceIdentity(spaceID, name: "Renamed before quit")
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

    /// A session whose Spaces and tabs share identities opens repaired: each
    /// gets an identity of its own, and a tab the repair gave a new identity
    /// wears the image of the tab in its place.
    func testCoreRepairPreservesAssetOwnershipWhenIdentitiesCollide() throws {
        var first = SessionState.Seed.preview.spaces[0]
        first.tabs = [first.tabs[0]]
        let source = first.tabs[0].id
        let store = BrowserStore(seed: SessionState.Seed(spaces: [first, first]), images: [source: Data([1])])
        let spaces = store.spaceModels
        XCTAssertEqual(spaces.count, 2)
        XCTAssertNotEqual(spaces.first?.id, spaces.last?.id)
        XCTAssertNotEqual(spaces.first?.profileID, spaces.last?.profileID)
        let tabs = spaces.compactMap { $0.tabs.models.first?.id }
        XCTAssertEqual(tabs.count, 2)
        XCTAssertEqual(Set(tabs).count, 2)
        for tab in tabs { XCTAssertEqual(store.core.state.favicons.image(of: tab), Data([1])) }
    }

    func testSpaceCommandsPreserveNativeRecordsAndPublishAcrossWindows() throws {
        let session = SessionState.Seed.preview
        let icon = Data([3, 2, 1])
        let tabID = session.spaces[0].tabs[0].id
        let store = BrowserStore(seed: session, images: [tabID: icon])
        let other = store.makeWindowStore(BrowserWindowOpening(restoresTabs: false))
        let id = session.spaces[0].id
        store.updateSpaceIdentity(id, name: "  Research  ")
        XCTAssertEqual(other.spaceModel(id)?.settings.name, "Research")
        XCTAssertEqual(other.core.state.favicons.image(of: tabID), icon)
        XCTAssertNil(other.selectedTabID(in: id))
        store.addSpace()
        XCTAssertEqual(store.spaceModels.count, session.spaces.count + 1)
        XCTAssertEqual(other.spaceModels.count, store.spaceModels.count)
        XCTAssertEqual(other.selectedSpaceID, id)
        XCTAssertEqual(store.spaceModels.last?.settings.name, "Space 3")
        let folderID = try XCTUnwrap(
            store.addFolder(title: "Research", color: BrandColor(red: 0.1, green: 0.5, blue: 0.5), in: id))
        XCTAssertEqual(
            other.spaceModel(id)?.folders.model(folderID)?.value.color, BrandColor(red: 0.1, green: 0.5, blue: 0.5))
        XCTAssertTrue(store.setFolderColor(folderID, in: id, color: BrandColor(red: 0.9, green: 0.7, blue: 0.2)))
        XCTAssertEqual(
            other.spaceModel(id)?.folders.model(folderID)?.value.color, BrandColor(red: 0.9, green: 0.7, blue: 0.2))
        XCTAssertNil(store.localSyncErrorDescription)
    }

    func testDirectCommandsKeepAssetsAndSaveNoWindowSelection() async throws {
        var original = SessionState.Seed.preview
        let spaceID = original.spaces[0].id
        let tabID = original.spaces[0].tabs[0].id
        let icon = Data([1, 2, 3])
        original.spaces[0].history.append(
            HistoryEntryState(url: try XCTUnwrap(URL(string: "https://example.org/direct")), title: "Visit"))
        let favicons = InMemoryBrowserFaviconStore()
        favicons.reconcile(icon, tabID: tabID)
        let harness = try BrowserStoredSessionHarness(seed: original, favicons: favicons)
        let store = harness.store
        store.selectPresentedSpace(original.spaces[1].id)
        XCTAssertTrue(store.setTabCustomTitle("Core command", for: tabID, in: spaceID))
        XCTAssertEqual(store.core.state.favicons.image(of: tabID), icon)
        XCTAssertEqual(store.spaceModel(spaceID)?.history.entries.map(\.id), original.spaces[0].history.map(\.id))
        await store.flushPendingSyncPersistence()
        XCTAssertEqual(try harness.stored().session.space(id: spaceID)?.tab(id: tabID)?.customTitle, "Core command")
        let saved = try XCTUnwrap(try harness.storedPart("core"))
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        let spaces = try XCTUnwrap(stored["spaces"] as? [[String: Any]])
        XCTAssertNil(stored["selectedSpaceID"], "A save never stores a window's selection")
        XCTAssertTrue(spaces.allSatisfy { $0["selectedTabID"] == nil })
    }

    /// An installed release kept the viewed Space and each Space's tab inside
    /// its stored session, and each window's record in its defaults. The
    /// session still loads; a window without a record opens on the launch Space
    /// with the tabs the release showed, a record written before windows
    /// remembered their Spaces folds them in once, its sidebar layout comes
    /// across, and the session saved next holds none of it.
    func testLegacyStoredSelectionAndWindowRecordsComeAcrossOnceAndLeaveTheSavedSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "crest.core-authority-test.legacy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let icons = InMemoryBrowserFaviconStore()
        let installed = SessionState.Seed.preview
        // A window without a record opens the first Space; per-Space tabs
        // still come from the older selection.
        let space = installed.spaces[1]
        let fallback = fallbackTabs(space)[space.id]
        let tab = try XCTUnwrap(space.tabs.first { $0.id != fallback })
        try BrowserInstalledRelease.write(installed, to: defaults, favicons: icons)
        // Spell the installed release's selection into its stored core.
        let storedCore = try XCTUnwrap(defaults.data(forKey: BrowserLegacySessionDefaults.coreKey))
        var core = try XCTUnwrap(JSONSerialization.jsonObject(with: storedCore) as? [String: Any])
        var spaces = try XCTUnwrap(core["spaces"] as? [[String: Any]])
        core["selectedSpaceID"] = space.id.uuidString
        spaces[1]["selectedTabID"] = tab.id.uuidString
        core["spaces"] = spaces
        defaults.set(try JSONSerialization.data(withJSONObject: core), forKey: BrowserLegacySessionDefaults.coreKey)
        // A window record written before windows remembered their Spaces.
        let recorded = UUID()
        let record: [String: Any] = [
            "id": ["rawValue": recorded.uuidString],
            "selectedSpaceID": ["rawValue": space.id.uuidString],
            "selectedTabIDsBySpace": [Any](),
            "sidebarWidth": 289.0,
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: [record]), forKey: BrowserWindowLayouts.legacyRecordsKey)

        let crest = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        let stored = try BrowserStore.migratedStorage(
            core: crest, legacy: BrowserLegacySessionDefaults(defaults: defaults, journalDefaults: [defaults]),
            favicons: icons, seed: nil)
        let store = BrowserStore.production(
            stored: stored, core: crest, favicons: icons)
        XCTAssertEqual(store.sessionSeed, BrowserStore(seed: installed).sessionSeed)
        XCTAssertEqual(store.selectedSpaceID, installed.spaces[0].id)
        XCTAssertEqual(store.selectedTabID(in: space.id), tab.id)

        let layouts = BrowserWindowLayouts(defaults: defaults)
        layouts.adoptLegacyRecords(into: crest)
        XCTAssertEqual(layouts.layout(for: recorded)?.sidebarWidth, 289)
        let window = store.makeWindowStore(BrowserWindowOpening(id: recorded, saved: true))
        XCTAssertEqual(window.selectedSpaceID, space.id)
        XCTAssertEqual(window.selectedTabID(in: space.id), tab.id)

        await store.flushPendingSyncPersistence()
        let relaunched = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        let reopened = try BrowserCoreSessionAuthority.openStored(in: relaunched, favicons: icons)
        let next = BrowserStore.production(
            stored: reopened, core: relaunched, favicons: icons)
        XCTAssertEqual(next.sessionSeed, store.sessionSeed)
        XCTAssertNil(next.selectedTabID(in: space.id), "The next save must not write the selection back")
    }

    /// Tab images stay native assets beside the core's file: the icon a page
    /// reports moves to its tab when the core records it and reaches the
    /// favicon store, a relaunch reattaches it, and a deleted tab's image is
    /// pruned.
    func testTabImagesFollowTheSessionIntoTheFaviconStore() async throws {
        let harness = try BrowserStoredSessionHarness(seed: .preview)
        let store = harness.store
        harness.core.engines.register(WebKitEngineBinding(), isDefault: true)
        let spaceID = try XCTUnwrap(store.shownSpace?.id)
        let tab = try XCTUnwrap(store.shownSpace?.tabs.models.first { $0.address != nil && $0.iconMode.followsPage })
        let url = try XCTUnwrap(tab.address)
        let icon = Data("captured".utf8)
        let page = try XCTUnwrap(store.openReportingPage(for: tab.id, in: spaceID))
        store.finishNavigation(of: page, to: url, titled: tab.title, icon: icon)
        XCTAssertEqual(store.core.state.favicons.image(of: tab.id), icon)
        XCTAssertEqual(harness.favicons.favicon(tabID: tab.id), icon)
        XCTAssertNil(harness.core.engines.takeIcon(of: page.id), "The image moved to the tab")
        page.release(keepingState: false)
        let relaunched = try await harness.relaunch()
        XCTAssertEqual(relaunched.store.core.state.favicons.image(of: tab.id), icon)
        store.deleteTab(tab.id, in: spaceID)
        XCTAssertNil(harness.favicons.favicon(tabID: tab.id))
    }

    /// Opening a new tab reuses an existing Start Page across relaunches.
    func testAnExistingStartPageIsReusedAfterRelaunch() async throws {
        var session = SessionState.Seed.preview
        for index in session.spaces.indices {
            session.spaces[index].tabs.removeAll { $0.url == nil && $0.nativeContent == nil }
        }
        var harness = try BrowserStoredSessionHarness(seed: session)
        let spaceID = try XCTUnwrap(harness.store.shownSpace?.id)
        let draft = try XCTUnwrap(harness.store.openNewTab())
        for _ in 0..<3 {
            harness = try await harness.relaunch()
            let store = harness.store
            store.selectSpace(spaceID)
            XCTAssertEqual(store.openNewTab(), draft)
            let space = try XCTUnwrap(store.spaceModel(spaceID))
            XCTAssertEqual(space.tabs.models.filter(\.isStartPage).map(\.id), [draft])
        }
    }

    // MARK: - Fixtures
    /// The tab the core would show first in `space`, as a window's tabs.
    private func fallbackTabs(_ space: SpaceState.Seed) -> [UUID: UUID] {
        guard let index = (try? CrestCore().query(FallbackTab(placements: space.tabs.map(\.placement))))?.index,
            space.tabs.indices.contains(index)
        else { return [:] }
        return [space.id: space.tabs[index].id]
    }
}
