import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserDataRetentionTests: XCTestCase {

    func testSessionCleanupAppliesEachSpacesOwnHistoryAndArchiveWindows() throws {
        let now = Date.now
        let oldDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        let recentDate = now.addingTimeInterval(-(29 * 24 * 60 * 60))
        var session = SessionState.Seed.preview
        let cleanedSpaceID = session.spaces[0].id
        let untouchedSpaceID = session.spaces[1].id
        Self.retain(.init(history: .thirtyDays, archive: .thirtyDays, downloads: .forever), in: &session.spaces[0])
        Self.retain(BrowsingPreferences.seeded.dataRetention, in: &session.spaces[1])
        session.spaces[0].history = [
            Self.history(title: "Old", visitedAt: oldDate),
            Self.history(title: "Recent", visitedAt: recentDate),
        ]
        session.spaces[1].history = [Self.history(title: "Other Space", visitedAt: oldDate)]
        session.spaces[0].archivedTabs = [
            Self.archive(title: "Old", archivedAt: oldDate),
            Self.archive(title: "Recent", archivedAt: recentDate),
        ]
        session.spaces[1].archivedTabs = [
            Self.archive(title: "Other Space", archivedAt: oldDate)
        ]

        let browser = BrowserStore(seed: session)

        browser.sweepExpiredBrowsingData()
        let swept = browser.sessionSeed
        XCTAssertEqual(
            try XCTUnwrap(swept.space(id: cleanedSpaceID)).history.map(\.title),
            ["Recent"]
        )
        XCTAssertEqual(
            try XCTUnwrap(swept.space(id: cleanedSpaceID)).archivedTabs.map(\.tab.title),
            ["Recent"]
        )
        XCTAssertEqual(
            try XCTUnwrap(swept.space(id: untouchedSpaceID)).history.map(\.title),
            ["Other Space"]
        )
        XCTAssertEqual(
            try XCTUnwrap(swept.space(id: untouchedSpaceID)).archivedTabs.map(\.tab.title),
            ["Other Space"]
        )
    }

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

    func testDownloadCenterSweepUsesSpacePoliciesAndDeterministicSpacing() {
        let now = Date(timeIntervalSinceReferenceDate: 60_000_000)
        let oldDate = now.addingTimeInterval(-(31 * 24 * 60 * 60))
        var session = SessionState.Seed.preview
        let cleanedProfileID = session.spaces[0].profileID
        Self.retain(.init(history: .forever, archive: .forever, downloads: .thirtyDays), in: &session.spaces[0])
        let store = BrowserStore(seed: session)
        let spaces = store.spaceModels
        let center = BrowserDownloadCenter()
        let expiredID = center.begin(
            profileID: cleanedProfileID,
            filename: "expired.pdf",
            createdAt: oldDate
        )
        center.send(FinishDownload(downloadID: expiredID, finalByteCount: nil))

        XCTAssertTrue(center.sweepExpiredRecords(in: spaces, now: now))
        XCTAssertTrue(center.items.isEmpty)
        XCTAssertFalse(
            center.sweepExpiredRecords(
                in: spaces,
                now: now.addingTimeInterval(
                    BrowserCurrentTabCleanupSchedule.minimumSweepSpacing - 1
                )
            )
        )
        XCTAssertTrue(
            center.sweepExpiredRecords(
                in: spaces,
                now: now.addingTimeInterval(
                    BrowserCurrentTabCleanupSchedule.minimumSweepSpacing
                )
            )
        )
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
