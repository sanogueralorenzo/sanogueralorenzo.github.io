import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserStoreWorkspaceTests: XCTestCase {
    func testAnEmptyWindowSelectionSurvivesOtherWindowsPublishingAndDeletingTabs() throws {
        let first = BrowserStore(seed: .preview, core: .hostingPages())
        let empty = first.makeWindowStore(BrowserWindowOpening(restoresTabs: false))
        let tab = try XCTUnwrap(first.shownSpace?.tabs.models.first)
        let ids = first.openTabIDs

        first.seedSelectedTabNavigation(to: tab.address, titled: "Changed elsewhere")

        XCTAssertNil(empty.shownTab)
        XCTAssertEqual(empty.openTabIDs, ids)
        first.deleteTab(tab.id, in: first.selectedSpaceID)
        XCTAssertNil(empty.shownTab)
        XCTAssertFalse(empty.openTabIDs.contains(tab.id))
    }

    func testTemporaryWorkspaceBorrowsItsProfileButKeepsAllBrowsingRecordsLocal() async throws {
        let harness = try BrowserStoredSessionHarness(seed: .preview)
        harness.core.engines.register(WebKitEngineBinding(), isDefault: true)
        let source = harness.store
        let sourceSpace = try XCTUnwrap(source.shownSpace)
        let original = source.sessionSeed
        let temporary = try XCTUnwrap(
            source.makeTemporaryWindowStore(in: BrowserSpaceRuntimeAssignment(space: sourceSpace)))

        XCTAssertTrue(temporary.isTemporaryWorkspace)
        XCTAssertFalse(temporary.family === source.family)
        XCTAssertFalse(temporary.syncsSession)
        XCTAssertEqual(temporary.shownSpace?.profileID, sourceSpace.profileID)
        XCTAssertEqual(temporary.shownSpace?.settings.browsingPreferences, sourceSpace.settings.browsingPreferences)
        XCTAssertEqual(temporary.shownSpace?.settings.credentialPreferences, sourceSpace.settings.credentialPreferences)
        XCTAssertTrue(try XCTUnwrap(temporary.shownSpace).tabs.models.isEmpty)
        XCTAssertTrue(try XCTUnwrap(temporary.shownSpace).folders.models.isEmpty)
        XCTAssertNil(temporary.shownTab)

        let url = try XCTUnwrap(URL(string: "https://temporary.crest.test/local"))
        let tabID = try XCTUnwrap(temporary.openNewTab(url: url))
        let page = try XCTUnwrap(temporary.openReportingPage(for: nil))
        temporary.finishNavigation(of: page, to: url, titled: "Temporary visit")
        page.release(keepingState: false)
        temporary.pinTab(tabID)
        temporary.deleteTab(tabID, in: sourceSpace.id)

        XCTAssertEqual(source.sessionSeed, original)
        XCTAssertEqual(temporary.shownSpace?.history.entries.first?.url, url.absoluteString)
        XCTAssertEqual(temporary.shownSpace?.archive.entries.first?.tab.id, tabID)
        // Nothing the temporary workspace did reaches its source's file.
        await temporary.flushPendingSyncPersistence()
        await source.flushPendingSyncPersistence()
        XCTAssertEqual(try harness.stored().session, original)
    }

    func testTemporaryWorkspaceFollowsItsSourceKeepingLocalOrganizationAndClosesOnAReplacedProfile() throws {
        let source = BrowserStore(seed: .preview)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(source.shownSpace))
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let url = try XCTUnwrap(URL(string: "https://temporary.crest.test/keep"))
        let tabID = try XCTUnwrap(temporary.openNewTab(url: url))
        let folderID = try XCTUnwrap(temporary.addFolder(title: "Local folder", in: assignment.spaceID))
        temporary.pinTab(tabID)
        // The source's edit reaches the temporary workspace with the edit itself.
        source.updateSpaceIdentity(assignment.spaceID, name: "Source renamed", symbol: "book", accent: .orange)

        XCTAssertTrue(temporary.family.isOpen)
        XCTAssertEqual(temporary.shownSpace?.settings.name, "Source renamed")
        XCTAssertEqual(temporary.shownSpace?.tabs.models.map(\.id), [tabID])
        XCTAssertEqual(temporary.shownSpace?.pinnedTabs.map(\.id), [tabID])
        XCTAssertEqual(temporary.shownSpace?.folders.models.map(\.id), [folderID])
        // A replacement of the Space's profile, as only the cloud makes, closes it.
        source.replaceProfileForTesting(of: assignment.spaceID)
        XCTAssertFalse(temporary.family.isOpen)
        XCTAssertTrue(temporary.spaceModels.isEmpty)
    }

    func testTemporaryProfileSettingsUseTheSourceAuthorityImmediately() throws {
        let source = BrowserStore(seed: .preview)
        let assignment = BrowserSpaceRuntimeAssignment(space: try XCTUnwrap(source.shownSpace))
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let originalTabs = source.openTabIDs
        XCTAssertTrue(temporary.profileSettingsBrowser.family === source.family)
        XCTAssertFalse(temporary.profileSettingsBrowser === source)
        temporary.addSpace()
        XCTAssertEqual(temporary.spaceModels.map(\.id), [assignment.spaceID])

        temporary.updateSpaceIdentity(assignment.spaceID, name: "Canonical rename", symbol: "book", accent: .orange)
        let duckDuckGo = try XCTUnwrap(BrowserSearchCatalog(core: temporary.core).provider(named: "duckDuckGo"))
        temporary.setSearch(duckDuckGo, suggestions: nil, in: assignment.spaceID)
        // Asking for authentication locks the Space, which this process has
        // not unlocked, so it comes last.
        temporary.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: assignment.spaceID)

        XCTAssertEqual(source.shownSpace?.settings.name, "Canonical rename")
        XCTAssertEqual(source.shownSpace?.settings.accessPolicy, .deviceOwnerAuthentication)
        XCTAssertEqual(source.shownSpace?.settings.browsingPreferences.selectedBuiltInEngine, .duckDuckGo)
        XCTAssertEqual(source.openTabIDs, originalTabs)
        XCTAssertTrue(try XCTUnwrap(temporary.shownSpace).tabs.models.isEmpty)
        XCTAssertTrue(source.family.beginDeletingSpace(assignment.spaceID))
        XCTAssertNil(temporary.shownSpace)
        XCTAssertNil(temporary.spaceModel(matching: assignment))
        source.family.finishDeletingSpace(assignment.spaceID)
    }

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

    func testTransferMovesTheSameTabBetweenFamiliesWithoutArchivingOrFillingTheEmptySource() throws {
        let folder = FolderState.Seed(title: "Source folder", symbol: "folder")
        let tab = TabState.Seed(
            title: "Move me", url: URL(string: "https://transfer.crest.test/live"),
            savedURL: URL(string: "https://transfer.crest.test/saved"),
            placement: .saved, folderID: folder.id)
        let icon = Data("icon".utf8)
        let space = SpaceState.Seed(
            name: "Source", symbol: "globe", accent: .indigo,
            folders: [folder], tabs: [tab])
        let companionTab = TabState.Seed(
            title: "Other Space", url: URL(string: "https://transfer.crest.test/other"), placement: .current)
        let companion = SpaceState.Seed(
            name: "Companion", symbol: "globe", accent: .orange,
            folders: [], tabs: [companionTab])
        let source = BrowserStore(
            seed: SessionState.Seed(spaces: [space, companion]), images: [tab.id: icon],
            showing: space.id, tabs: [space.id: tab.id, companion.id: companionTab.id])
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let temporary = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))

        XCTAssertTrue(source.canTransferTab(tab.id, matching: assignment, to: temporary, in: assignment))
        XCTAssertEqual(source.shownSpace?.tabs.models.map(\.id), [tab.id])
        XCTAssertTrue(try XCTUnwrap(temporary.shownSpace).tabs.models.isEmpty)
        XCTAssertTrue(source.transferTab(tab.id, matching: assignment, to: temporary, in: assignment))

        XCTAssertTrue(try XCTUnwrap(source.shownSpace).tabs.models.isEmpty)
        XCTAssertNil(source.shownTab)
        XCTAssertTrue(try XCTUnwrap(source.shownSpace).archive.entries.isEmpty)
        XCTAssertEqual(source.shownSpace?.folders.models.map(\.id), [folder.id])
        XCTAssertEqual(temporary.shownTab?.id, tab.id)
        XCTAssertEqual(temporary.core.state.favicons.image(of: tab.id), icon)
        XCTAssertEqual(temporary.shownTab?.address?.absoluteString, tab.url)
        XCTAssertEqual(temporary.shownTab?.placement, .current)
        XCTAssertNil(temporary.shownTab?.folderID)
        XCTAssertNil(temporary.shownTab?.savedURL)
        XCTAssertNil(source.shownTab)
        XCTAssertTrue(try XCTUnwrap(source.shownSpace).tabs.models.isEmpty)

        XCTAssertTrue(temporary.transferTab(tab.id, matching: assignment, to: source, in: assignment))
        XCTAssertEqual(source.shownTab?.id, tab.id)
        XCTAssertTrue(try XCTUnwrap(temporary.shownSpace).tabs.models.isEmpty)
        XCTAssertNil(temporary.shownTab)
        XCTAssertTrue(try XCTUnwrap(temporary.shownSpace).archive.entries.isEmpty)
    }

    func testTransferRejectsStaleAssignmentsAtomically() throws {
        let source = BrowserStore(seed: .preview)
        let space = try XCTUnwrap(source.shownSpace)
        let tab = try XCTUnwrap(space.tabs.models.first)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let destination = try XCTUnwrap(source.makeTemporaryWindowStore(in: assignment))
        let stale = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: UUID())
        let beforeSource = source.sessionSeed
        let beforeDestination = destination.sessionSeed

        XCTAssertFalse(source.canTransferTab(tab.id, matching: stale, to: destination, in: assignment))
        XCTAssertFalse(source.canTransferTab(tab.id, matching: assignment, to: destination, in: stale))
        XCTAssertFalse(source.transferTab(tab.id, matching: stale, to: destination, in: assignment))
        XCTAssertFalse(source.transferTab(tab.id, matching: assignment, to: destination, in: stale))
        XCTAssertEqual(source.sessionSeed, beforeSource)
        XCTAssertEqual(destination.sessionSeed, beforeDestination)
    }

}

@MainActor
private final class WorkspaceDataDeleter: BrowserSpaceDataDeleting {
    var wasCalled = false

    func deleteData(for space: BrowserSpaceRuntimeAssignment) async throws {
        wasCalled = true
    }
}
