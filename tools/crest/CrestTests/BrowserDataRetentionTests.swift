import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserDataRetentionTests: XCTestCase {

    func testShorteningRetentionImmediatelyDeletesExistingRecordsAndStagesTombstones() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 20_000_000)
        let oldDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        var session = SessionState.Seed.preview
        let spaceID = session.spaces[0].id
        let oldHistory = Self.history(title: "Expired", visitedAt: oldDate)
        let oldArchive = Self.archive(title: "Expired", archivedAt: oldDate)
        session.spaces[0].history = [oldHistory]
        session.spaces[0].archivedTabs = [oldArchive]
        let harness = try await BrowserStoredSessionHarness.staged(seed: session)
        let browser = harness.store

        browser.updateDataRetentionPreferences(
            .init(
                history: .thirtyDays,
                archive: .thirtyDays,
                downloads: .forever
            ),
            in: spaceID
        )
        await browser.flushPendingSyncPersistence()

        let savedSpace = try XCTUnwrap(browser.spaceModel(spaceID))
        XCTAssertTrue(savedSpace.history.entries.isEmpty)
        XCTAssertTrue(savedSpace.archive.entries.isEmpty)
        let journal = try harness.storedJournal()
        for (kind, id) in [(SyncRecordKind.history, oldHistory.id), (.archive, oldArchive.id)] {
            XCTAssertEqual(try XCTUnwrap(journal.record(kind, id)).deletionReason, .retention)
        }
    }

    @MainActor
    func testExpiredSyncedHistoryCannotReappearAfterMerge() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 30_000_000)
        let oldDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        var remoteSession = SessionState.Seed.preview
        let spaceID = remoteSession.spaces[0].id
        let history = Self.history(title: "Expired Remote", visitedAt: oldDate)
        Self.retain(.init(history: .thirtyDays, archive: .forever, downloads: .forever), in: &remoteSession.spaces[0])
        remoteSession.spaces[0].history = [history]
        let remote = try await BrowserStoredSessionHarness.staged(seed: remoteSession)
        var localSession = remoteSession
        localSession.spaces[0].history = []
        let device = try await BrowserStoredSessionHarness.staged(seed: localSession)

        try device.deliverNow(MergeSyncRecords(records: try await remote.pendingRecords()))

        XCTAssertTrue(try XCTUnwrap(device.store.spaceModel(spaceID)).history.entries.isEmpty)
        let record = try XCTUnwrap(try device.storedJournal().record(.history, history.id))
        XCTAssertEqual(record.deletionReason, .retention)
    }

    private static func history(title: String, visitedAt: Date) -> HistoryEntryState {
        HistoryEntryState(
            url: URL(string: "https://\(title.lowercased().replacingOccurrences(of: " ", with: "-")).example")!,
            title: title,
            firstVisitedAt: visitedAt,
            lastVisitedAt: visitedAt
        )
    }

    private static func archive(title: String, archivedAt: Date) -> ArchivedTabState.Seed {
        ArchivedTabState.Seed(
            tab: TabState.Seed(
                title: title,
                url: URL(string: "https://\(title.lowercased().replacingOccurrences(of: " ", with: "-")).example"),
                placement: .current,
                lastActivatedAt: archivedAt
            ),
            archivedAt: archivedAt,
            reason: .closed
        )
    }

    /// Gives the seeded `space` the retention windows `retention` names.
    private static func retain(_ retention: DataRetentionPreferences, in space: inout SpaceState.Seed) {
        space.settings.browsingPreferences.dataRetention = retention
    }
}
