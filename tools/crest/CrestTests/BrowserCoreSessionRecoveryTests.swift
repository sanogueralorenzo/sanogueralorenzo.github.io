import Foundation
import XCTest

@testable import Crest

/// The launch's side of the core's session file: the recovery screen restores
/// the checkpoint and launches again, a session from a newer release offers no
/// rollback, the cloud cursor restarts from a full pull, and an upgrade hands
/// the installed release's defaults to the core. The file-level contracts of
/// restore and adoption are the core's own tests.
@MainActor
final class BrowserCoreSessionRecoveryTests: XCTestCase {
    func testTheRecoveryScreenRestoresTheCheckpointAndThenLaunches() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Launch repair names a launch Space; this one already has it.
        var original = SessionState.Seed.preview
        original.defaultSpaceID = original.spaces[0].id
        // The journal of a device that staged the session.
        let staged = try await BrowserStoredSessionHarness.staged(seed: original)
        let journalData = try XCTUnwrap(try staged.storedPart("journal"))
        let journal = try StoredSyncJournal(journalData)
        do {
            let core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
            try BrowserInstalledRelease.adopt(original, journalData: journalData, into: core)
        }
        try Data("unreadable original".utf8).write(to: directory.appendingPathComponent("session.sqlite"))
        var successfulLaunches = 0
        let launch = BrowserApplicationLaunch {
            do {
                let core = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
                successfulLaunches += 1
                return core
            } catch { throw BrowserSessionStartupFailure(storageDirectory: directory, underlying: error) }
        }
        XCTAssertNil(launch.value)
        XCTAssertEqual(successfulLaunches, 0)
        XCTAssertNotNil(launch.failure?.checkpointDate)

        launch.restore()

        XCTAssertNil(launch.recoveryError)
        XCTAssertEqual(successfulLaunches, 1)
        let relaunched = try XCTUnwrap(launch.value)
        let restored = try BrowserCoreSessionAuthority.openStored(
            in: relaunched, favicons: InMemoryBrowserFaviconStore())
        let recovered = try BrowserStoredSessionHarness.storedJournal(in: directory)
        XCTAssertEqual(
            relaunched.state.workspaces[restored.workspaceID]?.sessionSeed, BrowserStore(seed: original).sessionSeed)
        XCTAssertNotEqual(recovered.deviceID, journal.deviceID)
        XCTAssertEqual(recovered.recordsJSON, journal.recordsJSON)
        // The core starts the cloud transport over from a full pull once it
        // opens the transport's state.
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("session.sqlite.cloud-recovery").path))
    }

    func testAnUnusableCheckpointReportsAnErrorAndANewerSessionOffersNoRollback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("session.sqlite")
        let original = Data("original bytes".utf8)
        try original.write(to: file)
        try Data("invalid checkpoint".utf8).write(to: BrowserSessionRecovery.checkpointURL(in: directory))
        let launch = BrowserApplicationLaunch {
            do { return try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path)) } catch {
                throw BrowserSessionStartupFailure(storageDirectory: directory, underlying: error)
            }
        }
        launch.restore()
        XCTAssertNil(launch.value)
        XCTAssertNotNil(launch.recoveryError)
        XCTAssertEqual(try Data(contentsOf: file), original)

        let failure = BrowserSessionStartupFailure(
            storageDirectory: directory, underlying: Rejection.storageFromNewerApp(StorageFromNewerApp()))
        XCTAssertTrue(failure.requiresNewerApp)
        XCTAssertNil(failure.checkpointDate)
        XCTAssertThrowsError(try failure.restore())
    }

    /// What the installed release left in its defaults reaches the core: the
    /// session core, every Space's history key, the journal from the suite it
    /// moved to, and the tab images already in the favicon store. The values
    /// stay for a rollback, and a later launch keeps the carried session.
    func testAnUpgradeHandsTheInstalledDefaultsToTheCoreOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "com.pauldavis.crest.tests.upgrade." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let journalSuiteName = suiteName + ".journal"
        let journalDefaults = try XCTUnwrap(UserDefaults(suiteName: journalSuiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            journalDefaults.removePersistentDomain(forName: journalSuiteName)
        }
        let favicons = BrowserFaviconFileStore(
            rootDirectory: directory.appendingPathComponent("Favicons", isDirectory: true))
        let (installed, images) = makeInstalledSession()
        let expected = BrowserStore(seed: installed).sessionSeed
        try BrowserInstalledRelease.write(installed, images: images, to: defaults, favicons: favicons)
        await favicons.flushPendingWrites()
        // The journal of a device that staged the installed session.
        let staged = try await BrowserStoredSessionHarness.staged(seed: installed)
        let journalData = try XCTUnwrap(try staged.storedPart("journal"))
        let journal = try StoredSyncJournal(journalData)
        journalDefaults.set(journalData, forKey: BrowserLegacySessionDefaults.journalKey)
        let legacy = BrowserLegacySessionDefaults(defaults: defaults, journalDefaults: [journalDefaults, defaults])

        do {
            let crest = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
            let storage = try BrowserStore.migratedStorage(
                core: crest, legacy: legacy, favicons: favicons, seed: nil)
            let carried = try BrowserStoredSessionHarness.storedJournal(in: directory)
            let workspace = try XCTUnwrap(crest.state.workspaces[storage.workspaceID])
            XCTAssertEqual(workspace.sessionSeed, expected)
            XCTAssertTrue(
                workspace.spaces.models.allSatisfy { space in
                    space.tabs.models.contains { crest.state.favicons.image(of: $0.id) != nil }
                })
            XCTAssertEqual(carried.deviceID, journal.deviceID)
            XCTAssertEqual(carried.recordsJSON, journal.recordsJSON)
            XCTAssertNotNil(defaults.data(forKey: BrowserLegacySessionDefaults.coreKey))
        }

        defaults.set(try BrowserInstalledRelease.parts(of: nil).core, forKey: BrowserLegacySessionDefaults.coreKey)
        let relaunchedCore = try CrestCore(configuration: AppConfiguration(storageDirectory: directory.path))
        let relaunched = try BrowserStore.migratedStorage(
            core: relaunchedCore, legacy: legacy, favicons: favicons, seed: nil)
        XCTAssertEqual(relaunchedCore.state.workspaces[relaunched.workspaceID]?.sessionSeed, expected)
    }

    /// Spaces with distinct profiles, folders, a split, an archive, per-Space
    /// history, tab images and a locked Space, with the image each tab wears.
    private func makeInstalledSession() -> (SessionState.Seed, [UUID: Data]) {
        var session = SessionState.Seed.showcase
        var images: [UUID: Data] = [:]
        let epoch = Date(timeIntervalSince1970: 1_700_000_000)
        for index in session.spaces.indices {
            for tab in session.spaces[index].tabs.indices {
                images[session.spaces[index].tabs[tab].id] = Data(
                    repeating: UInt8(truncatingIfNeeded: index * 17 + tab), count: 512)
                // An icon a page supplied names where it came from, as launch
                // repair records for an icon that does not.
                session.spaces[index].tabs[tab].faviconURL = session.spaces[index].tabs[tab].url
            }
            session.spaces[index].history = (0..<12).map { entry in
                HistoryEntryState(
                    url: URL(string: "https://example.com/space-\(index)/page-\(entry)")!,
                    title: "Space \(index) page \(entry)",
                    firstVisitedAt: epoch,
                    lastVisitedAt: epoch.addingTimeInterval(Double(entry)),
                    visitCount: entry % 5 + 1)
            }
        }
        session.spaces[1].settings.accessPolicy = .deviceOwnerAuthentication
        session.defaultSpaceID = session.spaces[0].id
        return (session, images)
    }
}
