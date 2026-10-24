import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserStoreTests: XCTestCase {

    func testFreshInstallSeedPersistsButNeverStagesBeforeCloudBootstrap() async throws {
        let harness = try BrowserStoredSessionHarness(
            seed: nil, syncDeviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!)
        let store = harness.store

        store.openNewTab(
            url: try XCTUnwrap(URL(string: "https://example.com/before-first-sync"))
        )
        await store.flushPendingSyncPersistence()
        let outboundPending = try harness.core.query(PendingUploads()).records

        XCTAssertEqual(store.workspaceModel?.isDisposableSeed, true)
        XCTAssertTrue(try harness.storedJournal().records.isEmpty)
        XCTAssertTrue(try harness.storedJournal().pending.isEmpty)
        XCTAssertTrue(outboundPending.isEmpty)
        XCTAssertEqual(store.core.state.syncJournal?.pendingRecords, 0)
        XCTAssertTrue(store.core.state.syncsDisposableSeed)
    }

    func testFirstCloudBootstrapReplacesDisposableSeedInsteadOfMergingIt() async throws {
        let cloudSession = SessionState.Seed(spaces: [.blank(number: 1)])
        let cloud = try await BrowserStoredSessionHarness.uploaded(
            seed: cloudSession, syncDeviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000098")!)
        let cloudRecords = try await cloud.heldRecords()

        let harness = try BrowserStoredSessionHarness(
            seed: nil, syncDeviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000097")!)
        let store = harness.store
        let seededSpaceIDs = Set(store.spaceModels.map(\.id))

        try harness.deliverNow(ReplaceSeedWithCloudRecords(records: cloudRecords))

        XCTAssertEqual(store.workspaceModel?.isDisposableSeed, false)
        XCTAssertEqual(store.spaceModels.map(\.id), cloudSession.spaces.map(\.id))
        XCTAssertTrue(seededSpaceIDs.isDisjoint(with: store.spaceModels.map(\.id)))
        let held = try harness.storedJournal().records
        XCTAssertEqual(held.map(\.reference), cloudRecords.map { SyncRecordReference(kind: $0.kind, id: $0.id) })
        XCTAssertEqual(held.map(\.version), cloudRecords.map(\.version))
        XCTAssertTrue(try harness.storedJournal().pending.isEmpty)
    }

    func testFirstCloudBootstrapClearsDisposableSeedWhenCloudIsEmpty() throws {
        let harness = try BrowserStoredSessionHarness(
            seed: nil, syncDeviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000096")!)
        let store = harness.store
        let seededSpaceIDs = Set(store.spaceModels.map(\.id))

        try harness.deliverNow(ReplaceSeedWithCloudRecords(records: []))

        XCTAssertEqual(store.workspaceModel?.isDisposableSeed, false)
        XCTAssertEqual(store.spaceModels.count, 1)
        XCTAssertEqual(store.shownSpace?.settings.name, "Space 1")
        XCTAssertTrue(seededSpaceIDs.isDisjoint(with: store.spaceModels.map(\.id)))
        XCTAssertTrue(try harness.storedJournal().records.isEmpty)
        XCTAssertTrue(try harness.storedJournal().pending.isEmpty)
    }

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

    func testOpeningABackgroundTabPreservesSelectionAndUsesTheExactOwningSpace() throws {
        let store = BrowserStore(seed: .preview)
        let selectedSpaceID = store.selectedSpaceID
        let targetSpace = try XCTUnwrap(
            store.spaceModels.first { $0.id != selectedSpaceID }
        )
        store.selectSpace(targetSpace.id)
        store.selectSpace(selectedSpaceID)
        let selectedTabID = try XCTUnwrap(store.shownTab?.id)
        let targetSelectedTabID = try XCTUnwrap(store.selectedTabID(in: targetSpace.id))
        let targetCount = targetSpace.tabs.models.count
        let url = try XCTUnwrap(URL(string: "https://example.com/background"))

        let openedID = try XCTUnwrap(
            store.openNewTab(
                url: url,
                in: targetSpace.id,
                selecting: false
            )
        )

        XCTAssertEqual(store.selectedSpaceID, selectedSpaceID)
        XCTAssertEqual(store.shownTab?.id, selectedTabID)
        XCTAssertEqual(store.selectedTabID(in: targetSpace.id), targetSelectedTabID)
        XCTAssertEqual(store.spaceModel(targetSpace.id)?.tabs.models.count, targetCount + 1)
        XCTAssertEqual(
            store.spaceModel(targetSpace.id)?.tabs.model(openedID)?.address,
            url
        )
        XCTAssertEqual(
            store.spaceModel(targetSpace.id)?.tabs.models.first { $0.id == openedID }?.placement,
            .current
        )
    }

    func testUpdatingSpaceBrowsingPreferencesPersistsOnlyThatSpacesChoices() async throws {
        let harness = try await BrowserStoredSessionHarness.uploaded(
            seed: .preview, syncDeviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!)
        let store = harness.store
        let selectedSpaceID = store.selectedSpaceID
        let otherSpace = try XCTUnwrap(
            store.spaceModels.first { $0.id != selectedSpaceID }
        )
        var preferences = try XCTUnwrap(store.spaceModel(selectedSpaceID)).settings.browsingPreferences
        let untouched = otherSpace.settings.browsingPreferences
        preferences.currentTabCleanup = .never
        let duckDuckGo = try XCTUnwrap(BrowserSearchCatalog(core: store.core).provider(named: "duckDuckGo"))

        store.updateBrowsingPreferences(preferences, in: selectedSpaceID)
        store.setSearch(duckDuckGo, suggestions: nil, in: selectedSpaceID)
        await store.flushPendingSyncPersistence()

        let updated = try XCTUnwrap(store.spaceModel(selectedSpaceID)?.settings.browsingPreferences)
        XCTAssertEqual(updated.currentTabCleanup, .never)
        XCTAssertEqual(updated.selectedBuiltInEngine, .duckDuckGo)
        XCTAssertFalse(updated.followsDefaultSearch)
        XCTAssertEqual(store.spaceModel(otherSpace.id)?.settings.browsingPreferences, untouched)
        XCTAssertTrue(try harness.storedJournal().isPending(.space, selectedSpaceID))
    }

    func testNormalStoreMutationStagesAndPersistsTheLocalSyncJournal() async throws {
        let harness = try await BrowserStoredSessionHarness.uploaded(
            seed: .preview, syncDeviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let store = harness.store

        store.openNewTab(url: try XCTUnwrap(URL(string: "https://example.com/synced")))
        await store.flushPendingSyncPersistence()

        let selectedID = try XCTUnwrap(store.shownTab?.id)
        XCTAssertTrue(try harness.storedJournal().isPending(.tab, selectedID))
        XCTAssertTrue(try harness.storedJournalIsPublished())
        XCTAssertNil(store.localSyncErrorDescription)
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

    func testDeletingAPinnedTabStagesItsExplicitTombstoneAndArchiveAudit() async throws {
        let session = SessionState.Seed.preview
        let pinnedTab = try XCTUnwrap(session.spaces[0].pinnedTabs.first)
        let deviceID = UUID(
            uuid: (
                0x44, 0x45, 0x4C, 0x45, 0x54, 0x45, 0x41, 0x55,
                0x44, 0x49, 0x54, 0x00, 0x00, 0x00, 0x00, 0x01
            )
        )
        let harness = try await BrowserStoredSessionHarness.uploaded(seed: session, syncDeviceID: deviceID)
        let store = harness.store

        store.deleteTab(pinnedTab.id, in: session.spaces[0].id)
        await store.flushPendingSyncPersistence()

        XCTAssertEqual(
            store.shownSpace?.archive.entries.first {
                $0.tab.id == pinnedTab.id
            }?.reason,
            .deleted
        )
        let journal = try harness.storedJournal()
        XCTAssertEqual(journal.record(.tab, pinnedTab.id)?.deletionReason, .explicitDelete)
        let archiveRecord = try XCTUnwrap(journal.record(.archive, pinnedTab.id))
        XCTAssertEqual(archiveRecord.value?["reason"] as? String, ArchiveReason.deleted.name)
    }

    func testFocusedWindowTabArchivePreservesAnotherWindowsSpaceSelection() throws {
        let root = BrowserStore(
            seed: .preview
        )
        let focusedWindow = root.makeWindowStore()
        let otherWindow = root.makeWindowStore()
        let work = try XCTUnwrap(focusedWindow.spaceModels.first)
        let personal = try XCTUnwrap(
            focusedWindow.spaceModels.first { $0.id != work.id }
        )
        let workTab = try XCTUnwrap(
            work.currentTabs.first { !$0.isStartPage }
        )
        let personalTab = try XCTUnwrap(personal.tabs.models.first)
        focusedWindow.selectSpace(work.id)
        focusedWindow.selectTab(workTab.id)
        otherWindow.selectSpace(personal.id)
        otherWindow.selectTab(personalTab.id)

        XCTAssertEqual(focusedWindow.archiveSelectedTab(), workTab.id)

        XCTAssertEqual(otherWindow.shownSpace?.id, personal.id)
        XCTAssertEqual(otherWindow.shownTab?.id, personalTab.id)
        XCTAssertTrue(
            try XCTUnwrap(otherWindow.spaceModel(work.id))
                .archive.contains(tabID: workTab.id)
        )
    }

    /// How many stages a burst makes is the core's (`EditsInQuickSuccessionStageOnceWithTheNewestSession`);
    /// showing a tab is an edit the journal stages with the newest session.
    func testRapidSelectionChangesStageTheLatestSession() async throws {
        let harness = try await BrowserStoredSessionHarness.staged(
            seed: .preview, syncDeviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!)
        let store = harness.store
        let tabs = try XCTUnwrap(store.shownSpace).tabs
        let selectableTabs = Array(tabs.models.prefix(3))
        XCTAssertGreaterThanOrEqual(selectableTabs.count, 2)

        for tab in selectableTabs {
            store.selectTab(tab.id)
        }
        await store.flushPendingSyncPersistence()

        let selectedID = try XCTUnwrap(store.shownTab?.id)
        let syncedTab = try XCTUnwrap(
            try harness.storedJournal().record(.tab, selectedID)?.value,
            "The latest selected tab should be present in the sync journal.")
        XCTAssertEqual(syncedTab["title"] as? String, store.shownTab?.title)
        XCTAssertEqual(syncedTab["url"] as? String, store.shownTab?.address?.absoluteString)
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

    func testDataStoreFailureKeepsTheSpaceAndItsCredentialsRetryable() async throws {
        let vault = InMemoryCredentialVault()
        let store = BrowserStore(
            seed: .preview,
            credentialVault: vault
        )
        let deletedSpace = try XCTUnwrap(store.spaceModels.first)
        let credential = try credential(
            spaceID: deletedSpace.id,
            username: "still-private"
        )
        try await vault.save(credential, in: deletedSpace.id)
        let deleter = RecordingSpaceDataDeleter(core: store.core, error: TestSpaceDeletionError.failed)

        await assertThrowsErrorAsync {
            try await store.deleteSpace(
                deletedSpace.id,
                dataDeleter: deleter
            )
        }

        XCTAssertEqual(deleter.deletedSpaces, [BrowserSpaceRuntimeAssignment(space: deletedSpace)])
        XCTAssertNotNil(store.spaceModel(deletedSpace.id))
        XCTAssertEqual(store.deletingSpaceIDs, [deletedSpace.id])
        XCTAssertEqual(store.workspaceModel?.spaceDeletions.first?.profileID, deletedSpace.profileID)
        let descriptors = await vault.descriptors(
            in: deletedSpace.id
        )
        XCTAssertEqual(
            descriptors,
            [credential.descriptor]
        )
    }

    func testDeletingTheLastSpaceIsRefusedBeforeAnyDataStoreMutation() async throws {
        var session = SessionState.Seed.preview
        session.spaces = [try XCTUnwrap(session.spaces.first)]
        let store = BrowserStore(
            seed: session
        )
        let deleter = RecordingSpaceDataDeleter(core: store.core)

        await assertThrowsErrorAsync(
            expected: Rejection.cannotDeleteLastSpace(CannotDeleteLastSpace())
        ) {
            try await store.deleteSpace(
                session.spaces[0].id,
                dataDeleter: deleter
            )
        }

        XCTAssertTrue(deleter.deletedSpaces.isEmpty)
        XCTAssertEqual(store.spaceModels.count, 1)
    }

    func testOpeningATabInASpaceBeingDeletedIsRefusedWithoutChangingSelection() async throws {
        let originalSession = SessionState.Seed.preview
        let store = BrowserStore(
            seed: originalSession
        )
        let destination = try XCTUnwrap(
            store.spaceModels.first {
                $0.id != store.selectedSpaceID
            }
        )
        let sourceSpaceID = store.selectedSpaceID
        let sourceTabCount = try XCTUnwrap(
            store.spaceModel(sourceSpaceID)?.tabs.models.count
        )
        let destinationTabCount = destination.tabs.models.count
        let deleter = SuspendingBrowserSpaceDataDeleter(core: store.core)
        let deletion = Task {
            try await store.deleteSpace(
                destination.id,
                dataDeleter: deleter
            )
        }
        await deleter.waitUntilDeletionStarts()
        let sessionBeforeOpening = store.sessionSeed

        XCTAssertTrue(store.deletingSpaceIDs.contains(destination.id))
        XCTAssertNil(
            store.openNewTab(
                url: try XCTUnwrap(URL(string: "https://deleting.crest.test")),
                in: destination.id,
                selecting: true
            )
        )
        XCTAssertEqual(store.selectedSpaceID, sourceSpaceID)
        XCTAssertEqual(
            store.spaceModel(sourceSpaceID)?.tabs.models.count,
            sourceTabCount
        )
        XCTAssertEqual(
            store.spaceModel(destination.id)?.tabs.models.count,
            destinationTabCount
        )
        XCTAssertEqual(store.sessionSeed, sessionBeforeOpening)

        deleter.finishDeletion()
        try await deletion.value
        XCTAssertNil(store.spaceModel(destination.id))
    }

    func testMovingATabIntoASpaceBeingDeletedIsRefusedWithoutChangingEitherSpace() async throws {
        let store = BrowserStore(
            seed: .preview,
            browsingMode: .privateBrowsing
        )
        let source = try XCTUnwrap(store.shownSpace)
        let sourceTab = try XCTUnwrap(source.tabs.models.first)
        let destination = try XCTUnwrap(
            store.spaceModels.first { $0.id != source.id }
        )
        let sourceTabIDs = source.tabs.models.map(\.id)
        let destinationTabIDs = destination.tabs.models.map(\.id)
        let deleter = SuspendingBrowserSpaceDataDeleter(core: store.core)
        let deletion = Task {
            try await store.deleteSpace(
                destination.id,
                dataDeleter: deleter
            )
        }
        await deleter.waitUntilDeletionStarts()

        XCTAssertFalse(
            store.canMoveTab(
                sourceTab.id,
                from: source.id,
                into: destination.id
            )
        )
        XCTAssertFalse(
            store.moveTab(
                sourceTab.id,
                from: source.id,
                into: destination.id
            )
        )
        XCTAssertEqual(store.spaceModel(source.id)?.tabs.models.map(\.id), sourceTabIDs)
        XCTAssertEqual(
            store.spaceModel(destination.id)?.tabs.models.map(\.id),
            destinationTabIDs
        )

        deleter.finishDeletion()
        try await deletion.value
    }

    func testSelectedSpaceBecomesUnavailableWhileItsDataDeletionIsInFlight() throws {
        let store = BrowserStore(
            seed: .preview,
            browsingMode: .privateBrowsing
        )
        let selectedSpace = try XCTUnwrap(store.shownSpace)
        let tabCount = selectedSpace.tabs.models.count

        XCTAssertTrue(store.family.beginDeletingSpace(selectedSpace.id))
        defer { store.family.finishDeletingSpace(selectedSpace.id) }

        XCTAssertNil(store.shownSpace)
        XCTAssertNil(store.shownTab)
        XCTAssertNil(store.openNewTab())
        XCTAssertEqual(
            store.spaceModel(selectedSpace.id)?.tabs.models.count,
            tabCount
        )
    }

    func testStaleDragCannotMoveATabFromAReplacementBrowsingProfile() throws {
        let store = BrowserStore(seed: .preview)
        let source = try XCTUnwrap(store.spaceModels.first)
        let destination = try XCTUnwrap(
            store.spaceModels.first { $0.id != source.id }
        )
        let tab = try XCTUnwrap(source.tabs.models.first)
        let staleItem = BrowserTabDragItem(
            tabID: tab.id,
            spaceID: source.id,
            profileID: source.profileID
        )
        store.replaceProfileForTesting(of: source.id)

        XCTAssertFalse(
            store.moveTab(
                staleItem,
                into: BrowserSpaceRuntimeAssignment(space: destination)
            )
        )
        XCTAssertTrue(
            try XCTUnwrap(store.spaceModel(source.id)).tabs.contains(tab.id)
        )
        XCTAssertFalse(
            try XCTUnwrap(store.spaceModel(destination.id)).tabs.contains(tab.id)
        )
    }

    func testWindowStateStorePersistsChromeOnlyForItsOwningWindow() {
        let browser = BrowserStore(seed: .preview)
        let layouts = BrowserWindowLayouts(defaults: nil)
        let firstWindow = BrowserWindowStateStore(id: UUID(), browser: browser, layouts: layouts)
        let secondWindow = BrowserWindowStateStore(id: UUID(), browser: browser, layouts: layouts)

        firstWindow.captureSidebar(width: 364, isPresented: false)
        secondWindow.captureSidebar(width: 278, isPresented: true)

        XCTAssertEqual(layouts.layout(for: firstWindow.id)?.sidebarWidth, 364)
        XCTAssertEqual(layouts.layout(for: firstWindow.id)?.sidebarIsPresented, false)
        XCTAssertEqual(layouts.layout(for: secondWindow.id)?.sidebarWidth, 278)
        XCTAssertEqual(layouts.layout(for: secondWindow.id)?.sidebarIsPresented, true)
    }

    func testWindowStoresShareBrowserMutationsButKeepIndependentSelections() throws {
        let firstWindow = BrowserStore(seed: .preview)
        let secondWindow = firstWindow.makeWindowStore()
        let work = try XCTUnwrap(firstWindow.spaceModels.first)
        let personal = try XCTUnwrap(firstWindow.spaceModels.last)
        let workTabID = try XCTUnwrap(work.tabs.models.first?.id)
        let personalTabID = try XCTUnwrap(personal.tabs.models.last?.id)
        let newURL = try XCTUnwrap(URL(string: "https://multiwindow.crest.test"))

        firstWindow.selectSpace(personal.id)
        firstWindow.selectTab(personalTabID)
        secondWindow.selectSpace(work.id)
        secondWindow.selectTab(workTabID)
        let openedTabID = try XCTUnwrap(firstWindow.openNewTab(url: newURL))

        XCTAssertEqual(firstWindow.shownSpace?.id, personal.id)
        XCTAssertEqual(firstWindow.shownTab?.id, openedTabID)
        XCTAssertEqual(secondWindow.shownSpace?.id, work.id)
        XCTAssertEqual(secondWindow.shownTab?.id, workTabID)
        XCTAssertEqual(
            secondWindow.spaceModel(personal.id)?.tabs.model(openedTabID)?.address,
            newURL
        )
        XCTAssertEqual(
            firstWindow.spaceModels.map(\.profileID),
            secondWindow.spaceModels.map(\.profileID)
        )
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

    func testIncomingSyncPreservesCustomizationWaitingForCoalescedPersistence() async throws {
        let session = SessionState.Seed.preview
        let harness = try await BrowserStoredSessionHarness.uploaded(seed: session)
        // Another device that holds what this one uploaded opens a tab.
        let remote = try await harness.joiningDevice()
        let newTab = try XCTUnwrap(
            remote.store.openSessionTab(
                .page(try XCTUnwrap(URL(string: "http://localhost:3000")), title: "Cloud page"),
                in: session.spaces[0].id, placement: .current, shouldSelect: false))
        let incoming = try await remote.pendingRecords()

        let store = harness.store
        let otherWindow = store.makeWindowStore()
        let spaceID = session.spaces[0].id
        var branding = try XCTUnwrap(store.spaceModel(spaceID)).settings.look
        branding.iconStyle = .layeredCrest
        branding.crest.symbol = .direwolf
        branding.crest.palette = [.ink, .gold, .ocean]
        otherWindow.updateSpaceBranding(branding, in: spaceID)
        // The look as the core keeps it, announcing the vocabulary it now draws with.
        branding = branding.normalized()

        // The receiving window must retain an edit from another window before
        // invalidating its delayed stage to apply this CloudKit batch.
        try harness.deliverNow(MergeSyncRecords(records: incoming))
        await otherWindow.flushPendingSyncPersistence()

        XCTAssertEqual(store.spaceModel(spaceID).map(\.settings.look), branding)
        XCTAssertEqual(otherWindow.spaceModel(spaceID).map(\.settings.look), branding)
        XCTAssertTrue(store.spaceModels[0].tabs.contains(newTab))
        XCTAssertTrue(try harness.storedJournal().isPending(.space, spaceID))
        try remote.deliverNow(MergeSyncRecords(records: try await harness.pendingRecords()))
        XCTAssertEqual(
            remote.store.spaceModel(spaceID).map(\.settings.look), branding)
    }

    func testSceneActivationSweepArchivesExpiredCurrentTabsInALongLivedSession() throws {
        let now = Date.now
        let fixture = Self.makeCleanupSweepFixture(now: now)
        let store = BrowserStore(seed: fixture.session)

        // Only launch and explicit actions used to sweep, so a store that is
        // already running still holds the expired tab before activation.
        let beforeSweep = try XCTUnwrap(store.spaceModel(fixture.sweepingSpaceID))
        XCTAssertTrue(beforeSweep.tabs.contains(fixture.expiredTabID))
        XCTAssertTrue(beforeSweep.archive.entries.isEmpty)

        store.sweepExpiredBrowsingData()

        let swept = try XCTUnwrap(store.spaceModel(fixture.sweepingSpaceID))
        XCTAssertFalse(swept.tabs.contains(fixture.expiredTabID))
        XCTAssertEqual(swept.archive.entries.map(\.tab.id), [fixture.expiredTabID])
        XCTAssertEqual(swept.archive.entries.first?.reason, .autoCleanup)
        XCTAssertEqual(try XCTUnwrap(swept.archive.entries.first?.archivedAt).timeIntervalSince(now), 0, accuracy: 60)
        // The stale selected tab and the start page stay put.
        XCTAssertTrue(swept.tabs.contains(fixture.selectedTabID))
        XCTAssertEqual(store.selectedTabID(in: fixture.sweepingSpaceID), fixture.selectedTabID)
        XCTAssertTrue(swept.tabs.contains(fixture.startPageID))
    }

    func testSceneActivationSweepRespectsEverySpaceCleanupPolicy() throws {
        let fixture = Self.makeCleanupSweepFixture(now: .now)
        let store = BrowserStore(
            seed: fixture.session
        )

        store.sweepExpiredBrowsingData()

        let neverSpace = try XCTUnwrap(store.spaceModel(fixture.neverSpaceID))
        XCTAssertTrue(neverSpace.tabs.contains(fixture.neverPolicyTabID))
        XCTAssertTrue(neverSpace.archive.entries.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(store.spaceModel(fixture.sweepingSpaceID)).archive.entries.count,
            1
        )
    }

    private struct CleanupSweepFixture {
        let session: SessionState.Seed
        let sweepingSpaceID: UUID
        let neverSpaceID: UUID
        let expiredTabID: UUID
        let selectedTabID: UUID
        let startPageID: UUID
        let neverPolicyTabID: UUID
    }

    /// A session that has been running long enough for cleanup to matter: one
    /// Space on the default 12 hour policy holding a stale selected tab, a stale
    /// start page and a stale unselected tab, plus one Space set to `.never`.
    private static func makeCleanupSweepFixture(now: Date) -> CleanupSweepFixture {
        let selected = TabState.Seed(
            title: "Reading now",
            url: URL(string: "https://example.com/selected"),
            placement: .current,
            lastActivatedAt: now.addingTimeInterval(-13 * 60 * 60)
        )
        let startPage = TabState.Seed.startPage(
            lastActivatedAt: now.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        let expired = TabState.Seed(
            title: "Old research",
            url: URL(string: "https://example.com/old"),
            placement: .current,
            lastActivatedAt: now.addingTimeInterval(-13 * 60 * 60)
        )
        let pinned = TabState.Seed(
            title: "Pinned",
            url: URL(string: "https://example.com/pinned"),
            placement: .pinned,
            lastActivatedAt: now.addingTimeInterval(-40 * 24 * 60 * 60)
        )
        let sweepingSpace = SpaceState.Seed(
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [pinned, selected, startPage, expired],
            browsingPreferences: .seeded(engine: .google, cleanup: .after12Hours)
        )
        let neverSelected = TabState.Seed(
            title: "Personal",
            url: URL(string: "https://example.com/personal"),
            placement: .current,
            lastActivatedAt: now
        )
        let neverPolicyTab = TabState.Seed(
            title: "Kept indefinitely",
            url: URL(string: "https://example.com/keep"),
            placement: .current,
            lastActivatedAt: now.addingTimeInterval(-31 * 24 * 60 * 60)
        )
        let neverSpace = SpaceState.Seed(
            name: "Personal",
            symbol: "house.fill",
            accent: .teal,
            folders: [],
            tabs: [neverSelected, neverPolicyTab],
            browsingPreferences: .seeded(engine: .duckDuckGo, cleanup: .never)
        )
        return CleanupSweepFixture(
            session: SessionState.Seed(spaces: [sweepingSpace, neverSpace]),
            sweepingSpaceID: sweepingSpace.id,
            neverSpaceID: neverSpace.id,
            expiredTabID: expired.id,
            selectedTabID: selected.id,
            startPageID: startPage.id,
            neverPolicyTabID: neverPolicyTab.id
        )
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

private enum TestSpaceDeletionError: Error {
    case failed
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

    func testClearingHistoryEmptiesOnlyTheSelectedSpace() throws {
        let store = BrowserStore(seed: .preview, core: .hostingPages())
        let selectedSpaceID = store.selectedSpaceID
        store.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/read")),
            titled: "Read"
        )

        store.clearHistory()

        XCTAssertTrue(try XCTUnwrap(store.spaceModel(selectedSpaceID)?.history.entries.isEmpty))
    }

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

    func testClearingCapturedHistoryRejectsAReplacementBrowsingProfile() throws {
        let store = BrowserStore(seed: .preview, core: .hostingPages())
        let initiatingSpace = try XCTUnwrap(store.shownSpace)
        store.seedVisit(
            to: try XCTUnwrap(URL(string: "https://example.com/private")),
            titled: "Private"
        )
        let request = BrowserSidebarClearHistoryConfirmation(
            assignment: BrowserSpaceRuntimeAssignment(space: initiatingSpace),
            spaceName: initiatingSpace.settings.name
        )
        let currentSpace = try XCTUnwrap(store.shownSpace)
        store.replaceProfileForTesting(of: currentSpace.id)
        let replacement = try XCTUnwrap(store.spaceModel(currentSpace.id))

        XCTAssertFalse(store.clearHistory(matching: request.assignment))
        XCTAssertEqual(
            store.spaceModel(replacement.id)?.history.entries.count,
            1
        )
    }

    func testRestoringCapturedArchiveRejectsAReplacementBrowsingProfile() throws {
        let store = BrowserStore(seed: .preview)
        let url = try XCTUnwrap(URL(string: "https://example.com/archive"))
        let tabID = try XCTUnwrap(store.openNewTab(url: url))
        store.closeTab(tabID)
        let original = try XCTUnwrap(store.shownSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: original)
        XCTAssertTrue(original.archive.entries.contains(where: { $0.tab.id == tabID }))
        store.replaceProfileForTesting(of: original.id)

        XCTAssertFalse(store.restoreArchivedTab(tabID, matching: assignment))
        XCTAssertTrue(
            try XCTUnwrap(store.spaceModel(original.id))
                .archive.entries.contains(where: { $0.tab.id == tabID })
        )
    }

    func testSavedTabsAndFolderDisclosureChangeTheirSpace() throws {
        let store = BrowserStore(seed: .preview)
        let spaceID = try XCTUnwrap(store.shownSpace?.id)
        let folderID = try XCTUnwrap(store.shownSpace?.folders.models.first?.id)

        XCTAssertTrue(store.setSavedTabsExpanded(false, in: spaceID))
        XCTAssertEqual(store.shownSpace?.settings.isSavedTabsExpanded, false)

        XCTAssertTrue(
            store.setFolderCollapsed(folderID, in: spaceID, isCollapsed: true)
        )
        XCTAssertEqual(
            store.shownSpace?.folders.models.first { $0.id == folderID }?.isCollapsed,
            true
        )
    }
}
