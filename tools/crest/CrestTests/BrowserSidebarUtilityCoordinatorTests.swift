import Foundation
import XCTest

@testable import Crest

/// The shared coordinator's behaviour, driven through a recording platform port
/// so the guards are tested apart from what either shell does afterwards. The
/// windowed shell's own binding is covered at the bottom; the compact shell's
/// is covered by `MobileBrowserSidebarUtilityCoordinatorTests`.
@MainActor
final class BrowserSidebarUtilityCoordinatorTests: XCTestCase {
    func testDownloadPolicyRequiresExactSelectedUnlockedProfileOwnership() {
        let context = makeContext()
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let exactItem = downloadItem(profileID: assignment.profileID, id: Self.uuid(20))
        let wrongProfileItem = downloadItem(
            profileID: Self.uuid(21),
            id: exactItem.id
        )
        let action = BrowserUtilityDownloadAction.clear(exactItem.id)

        XCTAssertEqual(
            action.downloadItem(
                matching: assignment, in: context.browser, accessController: context.access,
                itemsForProfile: { _ in [exactItem] }),
            exactItem
        )
        XCTAssertNil(
            action.downloadItem(
                matching: assignment, in: context.browser, accessController: context.access,
                itemsForProfile: { _ in [wrongProfileItem] })
        )

        context.browser.selectSpace(context.destination.id)
        XCTAssertNil(
            action.downloadItem(
                matching: assignment, in: context.browser, accessController: context.access,
                itemsForProfile: { _ in [exactItem] })
        )

        let lockedContext = makeContext(isProtected: true)
        let lockedAssignment = BrowserSpaceRuntimeAssignment(
            space: lockedContext.source
        )
        let lockedItem = downloadItem(
            profileID: lockedAssignment.profileID,
            id: Self.uuid(22)
        )
        XCTAssertNil(
            BrowserUtilityDownloadAction.clear(lockedItem.id).downloadItem(
                matching: lockedAssignment, in: lockedContext.browser, accessController: lockedContext.access,
                itemsForProfile: { _ in [lockedItem] })
        )

        let deletingContext = makeContext()
        let deletingAssignment = BrowserSpaceRuntimeAssignment(
            space: deletingContext.source
        )
        let deletingItem = downloadItem(
            profileID: deletingAssignment.profileID,
            id: Self.uuid(23)
        )
        XCTAssertTrue(
            deletingContext.browser.family.beginDeletingSpace(
                deletingContext.source.id
            )
        )
        defer {
            deletingContext.browser.family.finishDeletingSpace(
                deletingContext.source.id
            )
        }
        XCTAssertNil(
            BrowserUtilityDownloadAction.clear(deletingItem.id).downloadItem(
                matching: deletingAssignment, in: deletingContext.browser, accessController: deletingContext.access,
                itemsForProfile: { _ in [deletingItem] })
        )

        let replacementContext = makeContext()
        let replacementAssignment = BrowserSpaceRuntimeAssignment(
            space: replacementContext.source
        )
        let replacementItem = downloadItem(
            profileID: replacementAssignment.profileID,
            id: Self.uuid(24)
        )
        replaceProfile(
            of: replacementContext.source,
            in: replacementContext.browser
        )
        XCTAssertNil(
            BrowserUtilityDownloadAction.clear(replacementItem.id).downloadItem(
                matching: replacementAssignment, in: replacementContext.browser,
                accessController: replacementContext.access, itemsForProfile: { _ in [replacementItem] })
        )
    }

    private func makeContext(isProtected: Bool = false) -> Context {
        let selectedTab = TabState.Seed(
            id: Self.uuid(1),
            title: "Selected",
            url: URL(string: "about:blank"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let archivedTab = TabState.Seed(
            id: Self.uuid(2),
            title: "Archived",
            url: URL(string: "about:blank#archived"),
            placement: .current,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let archived = ArchivedTabState.Seed(
            tab: archivedTab,
            archivedAt: Date(timeIntervalSince1970: 1_700_000_002),
            reason: .closed
        )
        let history = HistoryEntryState(
            url: URL(fileURLWithPath: "/crest-sidebar-history"),
            title: "History",
            firstVisitedAt: Date(timeIntervalSince1970: 1_700_000_003),
            lastVisitedAt: Date(timeIntervalSince1970: 1_700_000_003)
        )
        let source = SpaceState.Seed(
            id: Self.uuid(3),
            profileID: Self.uuid(4),
            name: "Source",
            symbol: "sidebar.left",
            accent: .indigo,
            folders: [],
            tabs: [selectedTab],
            archivedTabs: [archived],
            history: [history],
            accessPolicy: isProtected ? .deviceOwnerAuthentication : .open
        )
        let destination = SpaceState.Seed(
            id: Self.uuid(5),
            profileID: Self.uuid(6),
            name: "Destination",
            symbol: "square.grid.2x2",
            accent: .rose,
            folders: [],
            tabs: []
        )
        let browser = BrowserStore(seed: SessionState.Seed(spaces: [source, destination]))
        let downloadCenter = BrowserDownloadCenter()
        let downloadItemID = downloadCenter.begin(
            profileID: source.profileID,
            filename: "Crest.dmg",
            createdAt: Date(timeIntervalSince1970: 1_700_000_004)
        )
        return Context(
            browser: browser,
            downloadCenter: downloadCenter,
            downloadItemID: downloadItemID,
            access: BrowserSpaceAccessController(
                authenticator: AcceptingAuthenticator()
            ),
            source: source,
            destination: destination,
            archived: archived,
            history: history
        )
    }

    private func replaceProfile(of space: SpaceState.Seed, in browser: BrowserStore) {
        browser.replaceProfileForTesting(of: space.id, with: Self.uuid(7))
    }

    private func downloadItem(profileID: UUID, id: UUID) -> DownloadState {
        DownloadState.fixture(
            id: id, profileID: profileID, createdAt: Date(timeIntervalSince1970: 1_700_000_004),
            filename: "Crest.dmg", progress: 0.5, phase: .downloading)
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x49, 0x44, 0x45, 0x42, 0x41, 0x52, 0x55,
                0x54, 0x49, 0x4C, 0x49, 0x54, 0x59, 0x00, finalByte
            ))
    }

    private struct Context {
        let browser: BrowserStore
        let downloadCenter: BrowserDownloadCenter
        let downloadItemID: UUID
        let access: BrowserSpaceAccessController
        let source: SpaceState.Seed
        let destination: SpaceState.Seed
        let archived: ArchivedTabState.Seed
        let history: HistoryEntryState
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
