import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserStoreTests: XCTestCase {

    func testPrivateBrowsingIsEphemeralAndCannotUseCrestPasswords() async throws {
        let store = BrowserStore.privateBrowsing(core: .hostingPages())
        let originalSpaceID = store.selectedSpaceID
        let originalProfileID = try XCTUnwrap(store.shownSpace?.profileID)
        let originalTabID = try XCTUnwrap(store.shownTab?.id)
        let url = try XCTUnwrap(URL(string: "https://private.crest.test/account"))

        XCTAssertTrue(store.isPrivateBrowsing)
        XCTAssertFalse(store.syncsSession)
        let privateSpace = try XCTUnwrap(store.shownSpace)
        let branding = privateSpace.settings.look
        let browsing = privateSpace.settings.browsingPreferences
        XCTAssertEqual(privateSpace.settings.name, "Private")
        XCTAssertEqual(privateSpace.settings.symbol, "eyeglasses")
        XCTAssertEqual(
            branding.colors,
            [
                BrandColor(
                    red: 0.58,
                    green: 0.30,
                    blue: 0.76
                )
            ]
        )
        XCTAssertEqual(branding.bannerPattern, .solid)
        // A private window searches with the device's private default and never suggests.
        XCTAssertTrue(browsing.followsDefaultSearch)
        XCTAssertFalse(browsing.followsDefaultSuggestions)
        XCTAssertFalse(browsing.searchSuggestionsEnabled)
        XCTAssertEqual(browsing.currentTabCleanup, .never)
        XCTAssertFalse(
            try XCTUnwrap(store.shownSpace)
                .settings.credentialPreferences.syncsCrestPasswordsWithICloud
        )
        let privateSuggestions = try await store.credentialSuggestions(for: url)
        XCTAssertTrue(privateSuggestions.isEmpty)

        do {
            _ = try await store.saveCredential(
                username: "private-user",
                password: "private-secret",
                for: url
            )
            XCTFail("Private browsing must not save a Crest Password")
        } catch {
            XCTAssertEqual(
                error as? CredentialVaultError,
                .unavailableInPrivateBrowsing
            )
        }

        store.openNewTab(url: url)
        store.seedVisit(to: url, titled: "Private account")
        XCTAssertFalse(try XCTUnwrap(store.shownSpace).history.entries.isEmpty)
        XCTAssertNotEqual(store.shownTab?.id, originalTabID)

        store.resetPrivateBrowsingSession()

        XCTAssertNotEqual(store.selectedSpaceID, originalSpaceID)
        XCTAssertNotEqual(store.shownSpace?.profileID, originalProfileID)
        XCTAssertNotEqual(store.shownTab?.id, originalTabID)
        XCTAssertEqual(store.spaceModels.count, 1)
        XCTAssertEqual(store.shownSpace?.tabs.models.count, 1)
        XCTAssertTrue(try XCTUnwrap(store.shownTab).isStartPage)
        XCTAssertTrue(try XCTUnwrap(store.shownSpace).history.entries.isEmpty)
        XCTAssertTrue(try XCTUnwrap(store.shownSpace).archive.entries.isEmpty)
    }

    func testClearHistoryStagesExplicitTombstones() async throws {
        var session = SessionState.Seed.preview
        let visitedAt = Date(timeIntervalSince1970: 100)
        session.spaces[0].history = [
            HistoryEntryState(
                url: try XCTUnwrap(URL(string: "https://example.com/private")),
                title: "Private",
                firstVisitedAt: visitedAt,
                lastVisitedAt: visitedAt
            )
        ]
        let historyID = try XCTUnwrap(session.spaces[0].history.first?.id)
        let harness = try await BrowserStoredSessionHarness.uploaded(
            seed: session, syncDeviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let store = harness.store

        store.clearHistory()
        await store.flushPendingSyncPersistence()

        let record = try XCTUnwrap(try harness.storedJournal().record(.history, historyID))
        XCTAssertEqual(record.deletionReason, .explicitDelete)
        XCTAssertTrue(record.isTombstone)
    }

    func testCloseAndRestoreUseRecoverableSupersessionRatherThanPermanentDelete() async throws {
        let session = SessionState.Seed.preview
        let harness = try await BrowserStoredSessionHarness.uploaded(
            seed: session, syncDeviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
        let store = harness.store
        let tabID = try XCTUnwrap(store.shownSpace?.currentTabs.first?.id)

        store.closeTab(tabID)
        await store.flushPendingSyncPersistence()

        XCTAssertEqual(try harness.storedJournal().record(.tab, tabID)?.deletionReason, .superseded)
        XCTAssertEqual(try harness.storedJournal().record(.archive, tabID)?.isTombstone, false)

        store.restoreArchivedTab(tabID)
        await store.flushPendingSyncPersistence()

        XCTAssertEqual(try harness.storedJournal().record(.tab, tabID)?.isTombstone, false)
        XCTAssertEqual(try harness.storedJournal().record(.archive, tabID)?.deletionReason, .superseded)
    }

    func testDeletingASpacePurgesCredentialsAndStagesExplicitSyncTombstones() async throws {
        let harness = try await BrowserStoredSessionHarness.uploaded(
            seed: .preview, syncDeviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!)
        let store = harness.store
        let vault = try XCTUnwrap(store.credentialVault as? InMemoryCredentialVault)
        let deletedSpace = try XCTUnwrap(store.spaceModels.first)
        let retainedSpace = try XCTUnwrap(
            store.spaceModels.first { $0.id != deletedSpace.id }
        )
        let deletedCredential = try credential(
            spaceID: deletedSpace.id,
            username: "delete-me"
        )
        let retainedCredential = try credential(
            spaceID: retainedSpace.id,
            username: "keep-me"
        )
        try await vault.save(deletedCredential, in: deletedSpace.id)
        try await vault.save(retainedCredential, in: retainedSpace.id)
        let deleter = RecordingSpaceDataDeleter(core: store.core)

        try await store.deleteSpace(deletedSpace.id, dataDeleter: deleter)
        await store.flushPendingSyncPersistence()

        XCTAssertEqual(deleter.deletedSpaces, [BrowserSpaceRuntimeAssignment(space: deletedSpace)])
        XCTAssertNil(store.spaceModel(deletedSpace.id))
        XCTAssertEqual(store.selectedSpaceID, retainedSpace.id)
        XCTAssertTrue(store.deletingSpaceIDs.isEmpty)
        let deletedDescriptors = await vault.descriptors(
            in: deletedSpace.id
        )
        let retainedDescriptors = await vault.descriptors(
            in: retainedSpace.id
        )
        XCTAssertTrue(deletedDescriptors.isEmpty)
        XCTAssertEqual(
            retainedDescriptors,
            [retainedCredential.descriptor]
        )
        let deletedRecord = try XCTUnwrap(try harness.storedJournal().record(.space, deletedSpace.id))
        XCTAssertTrue(deletedRecord.isTombstone)
        XCTAssertEqual(deletedRecord.deletionReason, .explicitDelete)
        XCTAssertTrue(try harness.storedJournalIsPublished())
    }

    func testDelayedStageFromAnotherWindowCannotDeleteANewerPinnedTab() async throws {
        let session = SessionState.Seed.preview
        let deviceID = UUID(
            uuid: (
                0x4D, 0x55, 0x4C, 0x54, 0x49, 0x57, 0x49, 0x4E,
                0x44, 0x4F, 0x57, 0x53, 0x00, 0x00, 0x00, 0x01
            )
        )
        let harness = try await BrowserStoredSessionHarness.uploaded(seed: session, syncDeviceID: deviceID)
        let firstWindow = harness.store
        let secondWindow = firstWindow.makeWindowStore()
        let existingTab = try XCTUnwrap(secondWindow.shownTab)

        XCTAssertTrue(
            secondWindow.setTabCustomTitle(
                "Queued before the pinned tab",
                for: existingTab.id,
                in: secondWindow.selectedSpaceID
            )
        )
        let pinnedTabID = try XCTUnwrap(
            firstWindow.openSessionTab(
                .page(try XCTUnwrap(URL(string: "https://pinned.crest.test")), title: "Pinned"),
                in: firstWindow.selectedSpaceID, placement: .pinned, shouldSelect: false
            )
        )

        await firstWindow.flushPendingSyncPersistence()
        await secondWindow.flushPendingSyncPersistence()

        let record = try XCTUnwrap(try harness.storedJournal().record(.tab, pinnedTabID))
        XCTAssertFalse(record.isTombstone)
        // Another device that takes everything this one holds shows the tab.
        let other = try await harness.joiningDevice()
        XCTAssertTrue(
            other.store.spaceModel(firstWindow.selectedSpaceID)?.tabs.contains(pinnedTabID) == true)
    }

    private func credential(
        spaceID: UUID,
        username: String
    ) throws -> BrowserCredential {
        let origin = try XCTUnwrap(
            CredentialOrigin(
                url: try XCTUnwrap(
                    URL(string: "https://credentials.crest.test")
                )
            )
        )
        return BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: spaceID,
                origin: origin,
                username: username
            ),
            password: "secret"
        )
    }
}

@MainActor
private final class RecordingSpaceDataDeleter: BrowserSpaceDataDeleting {
    private(set) var deletedSpaces: [BrowserSpaceRuntimeAssignment] = []
    private let core: CrestCore
    private let error: Error?

    init(core: CrestCore, error: Error? = nil) {
        self.core = core
        self.error = error
    }

    func deleteData(for space: BrowserSpaceRuntimeAssignment) async throws {
        deletedSpaces.append(space)
        if let error {
            throw error
        }
        try await core.eraseProfile(of: space)
    }
}

@MainActor
private func assertThrowsErrorAsync(
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected operation to throw", file: file, line: line)
    } catch {}
}

@MainActor
private func assertThrowsErrorAsync<T>(
    expected: T,
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async where T: Error & Equatable {
    do {
        try await operation()
        XCTFail("Expected operation to throw", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? T, expected, file: file, line: line)
    }
}

/// What page observations, history and organization edits change in the
/// shared session, how often they stage sync, and what they refuse.
@MainActor
final class BrowserStoreMutationTests: XCTestCase {

    func testClearingCapturedSpaceHistoryDoesNotRetargetAfterSelectionChanges() throws {
        let store = BrowserStore(seed: .preview, core: .hostingPages())
        let initiatingSpace = try XCTUnwrap(store.shownSpace)
        let laterSelectedSpace = try XCTUnwrap(
            store.spaceModels.first { $0.id != initiatingSpace.id }
        )
        let request = BrowserSidebarClearHistoryConfirmation(
            assignment: BrowserSpaceRuntimeAssignment(space: initiatingSpace),
            spaceName: initiatingSpace.settings.name
        )
        store.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/initiating")),
            titled: "Initiating"
        )
        store.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/later-selected")),
            titled: "Later selected",
            in: laterSelectedSpace.id
        )

        store.selectSpace(laterSelectedSpace.id)
        XCTAssertTrue(store.clearHistory(matching: request.assignment))

        XCTAssertEqual(store.selectedSpaceID, laterSelectedSpace.id)
        XCTAssertTrue(
            try XCTUnwrap(store.spaceModel(initiatingSpace.id))
                .history.entries.isEmpty
        )
        XCTAssertEqual(
            try XCTUnwrap(store.spaceModel(laterSelectedSpace.id))
                .history.entries.count,
            1
        )
    }

}
