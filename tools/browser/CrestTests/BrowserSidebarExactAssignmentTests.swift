import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserSidebarExactAssignmentTests: XCTestCase {
    func testRetainedRowPresentationNeverAuthorizesAStaleSpace() throws {
        let context = makeContext()
        let access = BrowserSpaceAccessController(authenticator: AcceptingAuthenticator())
        context.store.attachSpaceAccess(access)
        let lists = try XCTUnwrap(context.store.sidebarListContext(for: context.source.id, spaceAccess: access))
        let tab = try XCTUnwrap(lists.space.tabs.model(context.sourceTab.id))
        var row = BrowserSidebarTabRowConfiguration(tab: tab, context: lists, isSelected: true, isLoaded: true)
        XCTAssertTrue(row.isAvailableForDisplay, "The unprovided presentation keeps the live fallback")
        XCTAssertTrue(SidebarSpaceRole.permitsInteraction(isSelected: nil, isAvailable: row.isAvailableForDisplay))
        row.spacePresentation = SidebarSpacePresentation(space: lists.space, isUnlocked: true)

        context.store.selectSpace(context.destination.id)
        XCTAssertTrue(row.isAvailableForDisplay)
        XCTAssertTrue(
            SidebarSpaceRole.permitsInteraction(isSelected: true, isAvailable: row.isAvailableForDisplay),
            "A retained root can still have its preceding input role")
        XCTAssertFalse(row.isCurrentAndUnlocked, "An event must reject that stale current-page flag")

        XCTAssertTrue(row.isAvailableForDisplay, "The unchanged display value keeps the inactive page appearance")
        XCTAssertFalse(
            SidebarSpaceRole.permitsInteraction(isSelected: false, isAvailable: row.isAvailableForDisplay),
            "Inactive pages cannot register new drag sources")
        XCTAssertFalse(row.isCurrentAndUnlocked)
        row.spacePresentation = nil
        XCTAssertFalse(row.isAvailableForDisplay, "Mobile and previews retain their live selection gate")
        XCTAssertFalse(SidebarSpaceRole.permitsInteraction(isSelected: nil, isAvailable: row.isAvailableForDisplay))

        context.store.selectSpace(context.source.id)
        row.spacePresentation = SidebarSpacePresentation(space: lists.space, isUnlocked: true)
        XCTAssertTrue(row.isCurrentAndUnlocked)
        replaceProfile(of: context.source, in: context.store)
        XCTAssertFalse(row.isCurrentAndUnlocked, "A cached render value cannot authorize a replaced profile")

        let destination = try XCTUnwrap(context.store.spaceModel(context.destination.id))
        row.spacePresentation = SidebarSpacePresentation(space: destination, isUnlocked: true)
        XCTAssertFalse(row.isAvailableForDisplay, "A supplied foreign assignment must fail closed")
        XCTAssertFalse(SidebarSpaceRole.permitsInteraction(isSelected: true, isAvailable: row.isAvailableForDisplay))
        row.spacePresentation = SidebarSpacePresentation(
            space: try XCTUnwrap(context.store.spaceModel(context.source.id)), isUnlocked: false)
        XCTAssertFalse(row.isAvailableForDisplay)
        XCTAssertFalse(SidebarSpaceRole.permitsInteraction(isSelected: true, isAvailable: row.isAvailableForDisplay))

        let replaced = try XCTUnwrap(context.store.sidebarListContext(for: context.source.id, spaceAccess: access))
        var refreshed = BrowserSidebarTabRowConfiguration(
            tab: try XCTUnwrap(replaced.space.tabs.model(context.sourceTab.id)), context: replaced, isSelected: true,
            isLoaded: true)
        _ = context.store.deleteTab(context.sourceTab.id, matching: replaced.assignment)
        refreshed.spacePresentation = SidebarSpacePresentation(space: replaced.space, isUnlocked: true)
        XCTAssertFalse(refreshed.isAvailableForDisplay, "A removed member cannot remain enabled in a refreshed root")
        XCTAssertFalse(
            SidebarSpaceRole.permitsInteraction(isSelected: true, isAvailable: refreshed.isAvailableForDisplay))
    }

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

    func testCapturedTabRenameRejectsAReplacementBrowsingProfile() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        replaceProfile(of: context.source, in: context.store)

        XCTAssertFalse(
            context.store.setTabCustomTitle(
                "Replacement title",
                for: context.sourceTab.id,
                matching: assignment
            )
        )
        XCTAssertNil(
            try XCTUnwrap(context.store.spaceModel(context.source.id))
                .tabs.model(context.sourceTab.id)?
                .customTitle
        )
    }

    func testLiveTabDropRejectsAReplacementDestinationProfile() throws {
        let context = makeContext()
        let item = dragItem(for: context.sourceTab, in: context.source)
        let destinationAssignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        context.store.selectSpace(context.destination.id)
        replaceProfile(of: context.destination, in: context.store)

        XCTAssertFalse(
            context.store.moveTab(
                item,
                to: .saved,
                matching: destinationAssignment
            )
        )
        assertTab(
            context.sourceTab.id,
            staysIn: context.source.id,
            outside: context.destination.id,
            store: context.store
        )
    }

    func testLiveTabDropDoesNotFollowAChangedSelectedSpace() throws {
        let context = makeContext()
        let item = dragItem(for: context.sourceTab, in: context.source)
        let destinationAssignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        context.store.selectSpace(context.destination.id)
        context.store.selectSpace(context.source.id)

        XCTAssertFalse(
            context.store.moveTab(
                item,
                to: .saved,
                matching: destinationAssignment
            )
        )
        assertTab(
            context.sourceTab.id,
            staysIn: context.source.id,
            outside: context.destination.id,
            store: context.store
        )
    }

    func testLiveTabDropRejectsADeletedRenderedFolder() throws {
        let context = makeContext()
        let item = dragItem(for: context.sourceTab, in: context.source)
        context.store.selectSpace(context.destination.id)
        let assignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        let folderID = try XCTUnwrap(
            context.store.addFolder(
                title: "Rendered target",
                matching: assignment
            )
        )
        XCTAssertTrue(
            context.store.deleteFolder(folderID, matching: assignment)
        )

        XCTAssertFalse(
            context.store.moveTab(
                item,
                to: .saved,
                folderID: folderID,
                matching: assignment
            )
        )
        assertTab(
            context.sourceTab.id,
            staysIn: context.source.id,
            outside: context.destination.id,
            store: context.store
        )
    }

    func testLiveTabDropAcceptsExactSourceAndDestinationAssignments() throws {
        let context = makeContext()
        let item = dragItem(for: context.sourceTab, in: context.source)
        context.store.selectSpace(context.destination.id)
        let assignment = BrowserSpaceRuntimeAssignment(
            space: context.destination
        )
        let folderID = try XCTUnwrap(
            context.store.addFolder(
                title: "Exact target",
                matching: assignment
            )
        )

        XCTAssertTrue(
            context.store.moveTab(
                item,
                to: .saved,
                folderID: folderID,
                matching: assignment
            )
        )
        let movedTab = try XCTUnwrap(
            context.store.spaceModel(context.destination.id)?
                .tabs.model(context.sourceTab.id)
        )
        XCTAssertEqual(movedTab.placement, .saved)
        XCTAssertEqual(movedTab.folderID, folderID)
        XCTAssertFalse(
            try XCTUnwrap(context.store.spaceModel(context.source.id))
                .tabs.contains(context.sourceTab.id)
        )
    }

    func testStaleFolderDragRejectsAReplacementBrowsingProfile() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let folderID = try XCTUnwrap(
            context.store.addFolder(
                title: "Captured folder",
                matching: assignment
            )
        )
        let item = BrowserFolderDragItem(
            folderID: folderID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
        replaceProfile(of: context.source, in: context.store)

        XCTAssertFalse(
            context.store.moveFolder(
                item,
                matching: assignment,
                into: nil
            )
        )
        XCTAssertTrue(
            try XCTUnwrap(context.store.spaceModel(context.source.id))
                .folders.contains(folderID)
        )
    }

    func testCapturedFolderActionsRejectADeletingSpace() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let folderID = try XCTUnwrap(
            context.store.addFolder(
                title: "Captured folder",
                matching: assignment
            )
        )
        XCTAssertTrue(context.store.family.beginDeletingSpace(context.source.id))
        defer { context.store.family.finishDeletingSpace(context.source.id) }

        XCTAssertFalse(
            context.store.renameFolder(
                folderID,
                matching: assignment,
                title: "Rejected"
            )
        )
        XCTAssertNil(
            context.store.addFolder(
                title: "Rejected child",
                parentID: folderID,
                matching: assignment
            )
        )
        XCTAssertFalse(
            context.store.deleteFolder(folderID, matching: assignment)
        )
    }

    func testFolderDropRejectsAStaleRenderedSibling() throws {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let movedFolderID = try XCTUnwrap(
            context.store.addFolder(
                title: "Moved folder",
                matching: assignment
            )
        )
        let siblingID = try XCTUnwrap(
            context.store.addFolder(
                title: "Rendered sibling",
                matching: assignment
            )
        )
        let item = BrowserFolderDragItem(
            folderID: movedFolderID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
        XCTAssertTrue(
            context.store.deleteFolder(siblingID, matching: assignment)
        )

        XCTAssertFalse(
            context.store.moveFolder(
                item,
                matching: assignment,
                into: nil,
                before: siblingID
            )
        )
        XCTAssertEqual(
            context.store.spaceModel(context.source.id)?
                .folders.model(movedFolderID)?
                .parentID,
            nil
        )
    }

    func testClearHistoryConfirmationRejectsSelectionChange() throws {
        let context = makeContext()
        let access = BrowserSpaceAccessController(
            authenticator: AcceptingAuthenticator()
        )
        context.store.attachSpaceAccess(access)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let historyURL = try XCTUnwrap(
            URL(string: "https://sidebar-history.crest.test/selection")
        )
        context.store.seedVisit(to: historyURL, titled: "Selection", in: assignment.spaceID)
        let confirmation = try XCTUnwrap(
            BrowserSidebarClearHistoryConfirmation(
                for: try XCTUnwrap(context.store.spaceModel(context.source.id)), in: context.store,
                accessController: access)
        )
        context.store.selectSpace(context.destination.id)

        XCTAssertFalse(
            confirmation.isLive(in: context.store, accessController: access)
        )
        XCTAssertFalse(
            confirmation.clearHistory(in: context.store, accessController: access)
        )
        XCTAssertEqual(
            context.store.spaceModel(context.source.id)?.history.entries.count,
            1
        )
    }

    func testClearHistoryConfirmationRejectsRelockedSpace() async throws {
        let context = makeContext(sourceIsProtected: true)
        let access = BrowserSpaceAccessController(
            authenticator: AcceptingAuthenticator()
        )
        context.store.attachSpaceAccess(access)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let historyURL = try XCTUnwrap(
            URL(string: "https://sidebar-history.crest.test/relock")
        )
        let didUnlock = await access.unlock(try XCTUnwrap(context.store.spaceModel(context.source.id)))
        XCTAssertTrue(didUnlock)
        // The core records nothing into a Space this process holds locked.
        context.store.seedVisit(to: historyURL, titled: "Relock", in: assignment.spaceID)
        let confirmation = try XCTUnwrap(
            BrowserSidebarClearHistoryConfirmation(
                for: try XCTUnwrap(context.store.spaceModel(context.source.id)), in: context.store,
                accessController: access)
        )
        access.lock(context.source.id)

        XCTAssertFalse(
            confirmation.clearHistory(in: context.store, accessController: access)
        )
        XCTAssertEqual(
            context.store.spaceModel(context.source.id)?.history.entries.count,
            1
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

    private func dragItem(
        for tab: TabState.Seed,
        in space: SpaceState.Seed
    ) -> BrowserTabDragItem {
        BrowserTabDragItem(
            tabID: tab.id,
            spaceID: space.id,
            profileID: space.profileID
        )
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

    private func assertTab(
        _ tabID: UUID,
        staysIn sourceID: UUID,
        outside destinationID: UUID,
        store: BrowserStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            store.spaceModel(sourceID)?.tabs.contains(tabID) == true,
            file: file,
            line: line
        )
        XCTAssertFalse(
            store.spaceModel(destinationID)?.tabs.contains(tabID) == true,
            file: file,
            line: line
        )
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
