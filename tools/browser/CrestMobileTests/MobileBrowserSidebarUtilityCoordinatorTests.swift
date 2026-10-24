import Foundation
import XCTest

@testable import CrestMobile

/// The compact shell's binding of the shared utility coordinator. The guards
/// themselves belong to `BrowserSidebarUtilityCoordinatorTests`; what is tested
/// here is only where this shell sends an action once a guard lets it through.
@MainActor
final class MobileBrowserSidebarUtilityCoordinatorTests: XCTestCase {
    /// The compact shell has one page, so history is routed through the shell
    /// rather than opened as a second tab in place.
    func testHistoryIsRoutedThroughTheShellInsteadOfOpeningATab() throws {
        let context = makeContext()
        var selectedTabs: [UUID] = []
        var openedURLs: [URL] = []
        let coordinator = makeCoordinator(
            context,
            selectTab: { selectedTabs.append($0) },
            openURL: { openedURLs.append($0) }
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        let entry = try XCTUnwrap(context.browser.spaceModel(context.source.id)?.history.entries.first)

        coordinator.actions.restoreArchivedTab(context.archived.id, assignment)
        coordinator.actions.openHistoryEntry(entry, assignment)

        XCTAssertEqual(selectedTabs, [context.archived.id])
        XCTAssertEqual(openedURLs, [context.historyURL])
        XCTAssertFalse(
            try XCTUnwrap(
                context.browser.spaceModel(context.source.id)
            ).tabs.models.contains(where: { $0.address == context.historyURL })
        )
    }

    /// Finished files leave through the share sheet or the Files app, so those
    /// are the destinations the download surface offers.
    func testDownloadDestinationsAreTheCompactShellsExportRoutes() {
        let context = makeContext()
        let coordinator = makeCoordinator(
            context,
            selectTab: { _ in },
            openURL: { _ in }
        )

        XCTAssertEqual(coordinator.actions.downloadDestinations, [.share, .files])
    }

    /// Clearing a record goes through the store rather than straight to the
    /// download center, which is the only difference from the windowed shell.
    func testClearingADownloadGoesThroughThePageStore() {
        let context = makeContext()
        let coordinator = makeCoordinator(
            context,
            selectTab: { _ in },
            openURL: { _ in }
        )
        let assignment = BrowserSpaceRuntimeAssignment(space: context.source)
        // Only a download that ended can be cleared.
        context.pages.downloadCenter.cancel(context.downloadItemID)

        coordinator.actions.performDownloadAction(
            .clear(context.downloadItemID),
            assignment
        )

        XCTAssertTrue(context.pages.downloadCenter.items.isEmpty)
    }

    private func makeCoordinator(
        _ context: Context,
        selectTab: @escaping (UUID) -> Void,
        openURL: @escaping (URL) -> Void
    ) -> BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: context.browser,
            pages: context.pages,
            spaceAccess: context.access,
            selectTab: selectTab,
            openURL: openURL
        )
    }

    private func makeContext() -> Context {
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
        let historyURL = URL(fileURLWithPath: "/crest-mobile-sidebar-history")
        let history = HistoryEntryState(
            url: historyURL,
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
            tabs: [selectedTab],
            archivedTabs: [archived],
            history: [history]
        )
        let destination = SpaceState.Seed(
            id: Self.uuid(5),
            profileID: Self.uuid(6),
            name: "Destination",
            symbol: "square.grid.2x2",
            accent: .rose,
            tabs: []
        )
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [source, destination]),
            showing: source.id, tabs: [source.id: selectedTab.id],
            browsingMode: .privateBrowsing
        )
        let pages = MobileBrowserPageStore(browser: browser, usesEphemeralWebsiteDataStores: true)
        let downloadItemID = pages.downloadCenter.begin(
            profileID: source.profileID,
            filename: "Crest.ipa",
            createdAt: Date(timeIntervalSince1970: 1_700_000_004)
        )
        return Context(
            browser: browser,
            pages: pages,
            downloadItemID: downloadItemID,
            access: BrowserSpaceAccessController(
                authenticator: AcceptingAuthenticator()
            ),
            source: source,
            archived: archived,
            historyURL: historyURL
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x4D, 0x4F, 0x42, 0x49, 0x4C, 0x45, 0x55, 0x54,
                0x49, 0x4C, 0x49, 0x54, 0x59, 0x00, 0x00, finalByte
            ))
    }

    private struct Context {
        let browser: BrowserStore
        let pages: MobileBrowserPageStore
        let downloadItemID: UUID
        let access: BrowserSpaceAccessController
        let source: SpaceState.Seed
        let archived: ArchivedTabState.Seed
        let historyURL: URL
    }

    private final class AcceptingAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
