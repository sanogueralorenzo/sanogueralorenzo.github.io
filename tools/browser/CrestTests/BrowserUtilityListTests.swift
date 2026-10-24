import Foundation
import XCTest

@testable import Crest

final class BrowserUtilityListTests: XCTestCase {
    func testDownloadProgressDoesNotRestartUtilitySectionPreparation() {
        let id = UUID()
        let profileID = UUID()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: UUID(),
            profileID: profileID
        )
        let createdAt = Date.now
        let initial = DownloadState.fixture(
            id: id, profileID: profileID, createdAt: createdAt, filename: "Crest.dmg", progress: 0.1,
            phase: .downloading)
        let progressed = DownloadState.fixture(
            id: id, profileID: profileID, createdAt: createdAt, filename: "Crest.dmg", progress: 0.9,
            phase: .downloading)
        let finished = DownloadState.fixture(
            id: id, profileID: profileID, createdAt: createdAt, filename: "Crest.dmg", progress: 0.9,
            phase: .finished)

        let initialRequest = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: assignment,
            archivedTabs: [],
            history: [],
            downloads: [initial],
            searchText: "",
            filter: .all
        )
        let progressRequest = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: assignment,
            archivedTabs: [],
            history: [],
            downloads: [progressed],
            searchText: "",
            filter: .all
        )
        let finishedRequest = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: assignment,
            archivedTabs: [],
            history: [],
            downloads: [finished],
            searchText: "",
            filter: .all
        )

        XCTAssertEqual(initialRequest, progressRequest)
        XCTAssertNotEqual(initialRequest, finishedRequest)
    }

    func testUtilityPreparationIdentityIncludesTheExactSpaceProfileAssignment() {
        let spaceID = UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53, 0x54, 0x55, 0x54, 0x49,
                0x4C, 0x49, 0x54, 0x59, 0x53, 0x50, 0x41, 0x43
            ))
        let first = BrowserUtilityListRequest(
            surface: .history,
            assignment: BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: UUID(
                    uuid: (
                        0x43, 0x52, 0x45, 0x53, 0x54, 0x55, 0x54, 0x49,
                        0x4C, 0x49, 0x54, 0x59, 0x50, 0x52, 0x4F, 0x31
                    ))
            ),
            archivedTabs: [],
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )
        let replacement = BrowserUtilityListRequest(
            surface: .history,
            assignment: BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: UUID(
                    uuid: (
                        0x43, 0x52, 0x45, 0x53, 0x54, 0x55, 0x54, 0x49,
                        0x4C, 0x49, 0x54, 0x59, 0x50, 0x52, 0x4F, 0x32
                    ))
            ),
            archivedTabs: [],
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )

        XCTAssertNotEqual(first, replacement)
        XCTAssertFalse(first.hasSamePresentationOwnership(as: replacement))
    }

    func testDownloadReconciliationUsesLiveProgressWithoutSynthesizingRows() throws {
        let context = utilityDownloadContext()
        let prepared = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.1,
            phase: .downloading
        )
        let current = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.82,
            phase: .downloading
        )
        let newlyArrived = utilityDownload(
            id: identifier(0x65),
            profileID: context.assignment.profileID,
            progress: 0.3,
            phase: .downloading
        )

        let sections = BrowserUtilityListReconciliation.sections(
            preparedSections: [context.section(prepared)],
            surface: .downloads,
            assignment: context.assignment,
            downloads: [current, newlyArrived],
            searchText: "",
            filter: .all
        )

        let item = try XCTUnwrap(sections.first?.items.first)
        guard case .download(let download) = item else {
            return XCTFail("Expected a reconciled download")
        }
        XCTAssertEqual(download.id, context.itemID)
        XCTAssertEqual(download.progress, 0.82)
        XCTAssertEqual(sections.flatMap(\.items).count, 1)
    }

    func testDownloadReconciliationImmediatelyAppliesCurrentFilterState() throws {
        let context = utilityDownloadContext()
        let prepared = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.8,
            phase: .downloading
        )
        let finished = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 1,
            phase: .finished
        )
        let preparedSections = [context.section(prepared)]

        XCTAssertTrue(
            BrowserUtilityListReconciliation.sections(
                preparedSections: preparedSections,
                surface: .downloads,
                assignment: context.assignment,
                downloads: [finished],
                searchText: "",
                filter: .downloadsInProgress
            ).isEmpty
        )

        let allSections = BrowserUtilityListReconciliation.sections(
            preparedSections: preparedSections,
            surface: .downloads,
            assignment: context.assignment,
            downloads: [finished],
            searchText: "",
            filter: .all
        )
        let item = try XCTUnwrap(allSections.first?.items.first)
        guard case .download(let current) = item else {
            return XCTFail("Expected a current download")
        }
        XCTAssertEqual(current.phase, .finished)
    }

    func testDownloadReconciliationDropsRemovedAndForeignProfileRows() throws {
        let context = utilityDownloadContext()
        let prepared = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.2,
            phase: .downloading
        )
        let foreign = utilityDownload(
            id: context.itemID,
            profileID: identifier(0x66),
            progress: 0.9,
            phase: .finished
        )
        let exact = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.4,
            phase: .downloading
        )
        let preparedSections = [context.section(prepared)]

        for current in [[], [foreign]] {
            XCTAssertTrue(
                BrowserUtilityListReconciliation.sections(
                    preparedSections: preparedSections,
                    surface: .downloads,
                    assignment: context.assignment,
                    downloads: current,
                    searchText: "",
                    filter: .all
                ).isEmpty
            )
        }

        let reconciled = BrowserUtilityListReconciliation.sections(
            preparedSections: preparedSections,
            surface: .downloads,
            assignment: context.assignment,
            downloads: [foreign, exact, foreign],
            searchText: "",
            filter: .all
        )
        let item = try XCTUnwrap(reconciled.first?.items.first)
        guard case .download(let current) = item else {
            return XCTFail("Expected the exact-profile download")
        }
        XCTAssertEqual(current.profileID, context.assignment.profileID)
        XCTAssertEqual(current.progress, 0.4)
    }

    func testDownloadReconciliationEmitsDuplicatePreparedIDsOnce() throws {
        let context = utilityDownloadContext()
        let foreign = utilityDownload(
            id: context.itemID,
            profileID: identifier(0x66),
            progress: 0.1,
            phase: .downloading
        )
        let exact = utilityDownload(
            id: context.itemID,
            profileID: context.assignment.profileID,
            progress: 0.7,
            phase: .downloading
        )
        let preparedSections = [
            context.section(foreign),
            context.section(exact),
        ]

        let request = BrowserUtilityListRequest(
            surface: .downloads,
            assignment: context.assignment,
            archivedTabs: [],
            history: [],
            downloads: [foreign, exact, exact],
            searchText: "",
            filter: .all
        )
        XCTAssertEqual(request.downloads.map(\.id), [context.itemID])
        XCTAssertEqual(request.downloads.first?.profileID, context.assignment.profileID)

        let reconciled = BrowserUtilityListReconciliation.sections(
            preparedSections: preparedSections,
            surface: .downloads,
            assignment: context.assignment,
            downloads: [foreign, exact, exact],
            searchText: "",
            filter: .all
        )
        let items = reconciled.flatMap(\.items)
        XCTAssertEqual(items.count, 1)
        guard case .download(let current) = try XCTUnwrap(items.first) else {
            return XCTFail("Expected one exact-profile download")
        }
        XCTAssertEqual(current.profileID, context.assignment.profileID)
        XCTAssertEqual(current.progress, 0.7)
    }

    func testUtilityPreparationRefreshesAtTheNextRelevantBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from: "2026-08-08T00:00:00Z"))
        let visitDate = try XCTUnwrap(
            formatter.date(from: "2026-08-01T15:00:00Z")
        )
        let entry = HistoryEntryState(
            id: identifier(0x67),
            url: "file:///crest-preview/history",
            title: "History",
            firstVisitedAt: visitDate,
            lastVisitedAt: visitDate,
            visitCount: 1
        )
        let request = BrowserUtilityListRequest(
            surface: .history,
            assignment: utilityDownloadContext().assignment,
            archivedTabs: [],
            history: [entry],
            downloads: [],
            searchText: "",
            filter: .historyPastWeek
        )

        XCTAssertEqual(
            BrowserUtilityListPreparation.nextRefreshDate(
                for: request,
                now: now,
                calendar: calendar
            ),
            try XCTUnwrap(formatter.date(from: "2026-08-08T15:00:00Z"))
        )

        let emptyRequest = BrowserUtilityListRequest(
            surface: .history,
            assignment: utilityDownloadContext().assignment,
            archivedTabs: [],
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )
        XCTAssertNil(
            BrowserUtilityListPreparation.nextRefreshDate(
                for: emptyRequest,
                now: now,
                calendar: calendar
            )
        )
    }

    @MainActor
    func testDownloadRecordsRetainTheTimeUsedForListGrouping() {
        let center = BrowserDownloadCenter()
        let createdAt = Date(timeIntervalSince1970: 1_786_084_200)

        _ = center.begin(
            profileID: UUID(),
            filename: "crest.dmg",
            createdAt: createdAt
        )

        XCTAssertEqual(center.items.first?.createdAt, createdAt)
    }

    func testUtilitySectionsArePreparedAwayFromTheRenderPass() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-07T12:00:00Z")
        )
        let today = HistoryEntryState(
            id: UUID(),
            url: "https://example.com/today",
            title: "Today",
            firstVisitedAt: now,
            lastVisitedAt: now,
            visitCount: 1
        )
        let yesterdayDate = try XCTUnwrap(
            calendar.date(byAdding: .day, value: -1, to: now)
        )
        let yesterday = HistoryEntryState(
            id: UUID(),
            url: "https://example.com/yesterday",
            title: "Yesterday",
            firstVisitedAt: yesterdayDate,
            lastVisitedAt: yesterdayDate,
            visitCount: 1
        )
        let request = BrowserUtilityListRequest(
            surface: .history,
            assignment: BrowserSpaceRuntimeAssignment(
                spaceID: UUID(),
                profileID: UUID()
            ),
            archivedTabs: [],
            history: [yesterday, today],
            downloads: [],
            searchText: "",
            filter: .all
        )

        let sections = await Task.detached(priority: .userInitiated) {
            BrowserUtilityListPreparation.sections(
                for: request,
                now: now,
                calendar: calendar
            )
        }.value

        XCTAssertEqual(
            sections.map {
                localized($0.timeframe.title, locale: Locale(identifier: "en"))
            },
            ["Today", "1 day ago"]
        )
        XCTAssertEqual(sections.flatMap(\.items).count, 2)
    }

    @MainActor
    func testCommonListTriggerCanRouteANewDownloadNotificationToDownloads() {
        let presentation = BrowserUtilityPresentationState()

        presentation.toggleSwitcher(hasNewDownloads: true)

        XCTAssertTrue(presentation.isSwitcherExpanded)
        XCTAssertEqual(presentation.surface, .downloads)
    }

    @MainActor
    func testCommonListTriggerRestoresTheLastSurfaceAcrossPresentationStates() throws {
        let suiteName = "crest.tests.utility-presentation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let first = BrowserUtilityPresentationState(defaults: defaults)

        first.present(.history)
        first.dismiss()

        let restored = BrowserUtilityPresentationState(defaults: defaults)
        restored.toggleSwitcher()

        XCTAssertTrue(restored.isSwitcherExpanded)
        XCTAssertEqual(restored.surface, .history)
    }

    func testDownloadNotificationUsesTheNewestActiveTransferProgress() throws {
        let profileID = identifier(0x70)
        let older = DownloadState.fixture(
            id: identifier(0x71), profileID: profileID, createdAt: Date(timeIntervalSinceReferenceDate: 100),
            filename: "older.zip", progress: 0.8, phase: .downloading)
        let newest = DownloadState.fixture(
            id: identifier(0x72), profileID: profileID, createdAt: Date(timeIntervalSinceReferenceDate: 200),
            filename: "newest.pdf", progress: 0.35, phase: .downloading)

        XCTAssertEqual(
            try XCTUnwrap(
                [older, newest].notificationProgress
            ),
            0.35,
            accuracy: 0.001
        )
    }

    func testFinishedDownloadRowRevealsTheFileInFinder() {
        XCTAssertEqual(
            BrowserUtilityDownloadDestination.primary(
                for: .finished,
                among: [.open, .revealInFinder]
            ),
            .revealInFinder
        )
        XCTAssertNil(
            BrowserUtilityDownloadDestination.primary(
                for: .downloading,
                among: [.open, .revealInFinder]
            )
        )
    }

    @MainActor
    func testArchivePreparationSortsByTheTimeTheTabWasClosed() throws {
        let now = Date(timeIntervalSinceReferenceDate: 900)
        let older = ArchivedTabState.Seed(
            tab: TabState.Seed(
                id: identifier(0x73),
                title: "Older",
                url: URL(string: "https://example.com/older"),
                symbol: "globe",
                placement: .current,
                lastActivatedAt: Date(timeIntervalSinceReferenceDate: 800)
            ),
            archivedAt: Date(timeIntervalSinceReferenceDate: 850),
            reason: .closed
        )
        let newer = ArchivedTabState.Seed(
            tab: TabState.Seed(
                id: identifier(0x74),
                title: "Newer",
                url: URL(string: "https://example.com/newer"),
                symbol: "globe",
                placement: .current,
                lastActivatedAt: Date(timeIntervalSinceReferenceDate: 100)
            ),
            archivedAt: now,
            reason: .autoCleanup
        )
        let space = SpaceState.Seed(
            id: identifier(0x61), profileID: identifier(0x62), name: "Archive",
            symbol: "archivebox", accent: .indigo, folders: [], tabs: [], archivedTabs: [older, newer])
        let store = BrowserStore(seed: SessionState.Seed(spaces: [space]), showing: space.id)
        let request = BrowserUtilityListRequest(
            surface: .archive,
            assignment: utilityDownloadContext().assignment,
            archivedTabs: try XCTUnwrap(store.spaceModel(space.id)?.archive.entries),
            history: [],
            downloads: [],
            searchText: "",
            filter: .all
        )

        let sections = BrowserUtilityListPreparation.sections(
            for: request,
            now: now,
            calendar: .current
        )

        XCTAssertEqual(
            sections.flatMap(\.items).compactMap { item -> UUID? in
                guard case .archive(let archived) = item else { return nil }
                return archived.tab.id
            },
            [newer.id, older.id]
        )
    }

    private func localized(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
            .replacingOccurrences(of: "\u{2068}", with: "")
            .replacingOccurrences(of: "\u{2069}", with: "")
    }

    private func utilityDownloadContext() -> (
        assignment: BrowserSpaceRuntimeAssignment,
        itemID: UUID,
        section: (DownloadState) -> BrowserUtilityListSection
    ) {
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: identifier(0x61),
            profileID: identifier(0x62)
        )
        let now = Date(timeIntervalSinceReferenceDate: 807_969_600)
        var calendar = Calendar(identifier: .gregorian)
        if let timeZone = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = timeZone
        }
        let timeframe = BrowserUtilityTimeSection(
            date: now,
            now: now,
            calendar: calendar
        )
        return (
            assignment,
            identifier(0x63),
            { item in
                BrowserUtilityListSection(
                    timeframe: timeframe,
                    items: [.download(item)]
                )
            }
        )
    }

    private func utilityDownload(
        id: UUID,
        profileID: UUID,
        progress: Double,
        phase: DownloadPhase
    ) -> DownloadState {
        DownloadState.fixture(
            id: id,
            profileID: profileID,
            createdAt: Date(timeIntervalSinceReferenceDate: 807_969_600),
            filename: "Crest.dmg",
            destination: URL(filePath: "/crest-preview/Crest.dmg"),
            progress: progress,
            phase: phase
        )
    }

    private func identifier(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0, 0, 0, 0, 0, 0, 0x40, 0,
                0x80, 0, 0, 0, 0, 0, 0, finalByte
            )
        )
    }
}
