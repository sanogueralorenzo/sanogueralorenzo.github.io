import CloudKit
import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCloudSyncControllerTests: XCTestCase {
    func testAvailableAccountStartsAutomaticTransportWithoutForcingAManualSync() async throws {
        let core = CrestCore()
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(accountState: .available)
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )

        await controller.start()

        XCTAssertEqual(controller.accountState, .available)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertNotNil(controller.lastAttemptAt)
        XCTAssertNil(controller.lastSuccessAt)
        let transport = try XCTUnwrap(factory.transports.first)
        let startCount = await transport.startCount
        let syncCount = await transport.syncCount
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(syncCount, 0)

        await transport.emit(.fetched(recordCount: 4))
        await transport.emit(.uploaded(recordCount: 3))
        await controller.localChangesDidStage()

        XCTAssertEqual(controller.lastFetchedRecordCount, 4)
        XCTAssertEqual(controller.lastUploadedRecordCount, 3)
        XCTAssertNotNil(controller.lastSuccessAt)
        let notifyCount = await transport.notifyCount
        XCTAssertEqual(notifyCount, 1)
    }

    /// A core that cannot answer for this device's journal stops the start
    /// before anything reaches iCloud: its refusal never reads as a device
    /// with nothing to keep, which would take the cloud's content instead.
    func testAComparisonTheCoreRefusesStopsSyncWithoutTakingTheCloud() async throws {
        let core = try awaitingAccountDecision(CrestCore())
        let preferences = TestBrowserCloudSyncPreferences()
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: TestBrowserCloudSyncRemoteService(
                accountState: .available,
                snapshot: try await cloudRecords(of: SessionState.Seed(spaces: [.blank(number: 1)]))),
            transportFactory: factory
        )

        await controller.start()

        guard controller.phase == .failed else { return XCTFail("Sync started over a refused comparison.") }
        XCTAssertTrue(factory.transports.isEmpty)
        XCTAssertNil(controller.conflict)
        XCTAssertTrue(try core.query(CloudTransport()).awaitsAccountDecision)
    }

    func testDifferentAccountContentPausesForExplicitReconciliation() async throws {
        let device = try await syncedDevice()
        let local = try device.storedPart("journal")
        let localRecordCount = try device.storedJournal().records.count
        let cloud = try await cloudRecords(of: SessionState.Seed(spaces: [.blank(number: 1)]))
        _ = try awaitingAccountDecision(device.core)
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: cloud
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: device.core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )

        await controller.start()

        XCTAssertEqual(controller.phase, .needsReconciliation)
        XCTAssertEqual(
            controller.conflict,
            BrowserCloudSyncConflictSummary(
                localRecordCount: localRecordCount,
                cloudRecordCount: cloud.count,
                localSpaceCount: SessionState.Seed.preview.spaces.count,
                cloudSpaceCount: 1
            )
        )
        XCTAssertEqual(controller.observedCloudRecordCount, cloud.count)
        XCTAssertTrue(factory.transports.isEmpty)
        XCTAssertEqual(try device.storedPart("journal"), local, "Neither copy is replaced or overwritten")
    }

    func testUseICloudResolutionReplacesLocalContentAndClearsThePause() async throws {
        let device = try await syncedDevice()
        let cloudSession = SessionState.Seed(spaces: [.blank(number: 1)])
        _ = try awaitingAccountDecision(device.core)
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: try await cloudRecords(of: cloudSession)
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: device.core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )
        await controller.start()

        await controller.resolveUsingICloud()

        XCTAssertEqual(device.store.spaceModels.map(\.id), cloudSession.spaces.map(\.id))
        XCTAssertTrue(try device.core.query(PendingUploads()).records.isEmpty)
        let transport = try device.core.query(CloudTransport())
        XCTAssertFalse(transport.awaitsAccountDecision)
        XCTAssertFalse(transport.overwritesCloud)
        XCTAssertNil(controller.conflict)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testUseThisDeviceResolutionStagesAnOverwriteAndPersistsTheChoice() async throws {
        let device = try await syncedDevice()
        let local = device.store.sessionSeed
        _ = try awaitingAccountDecision(device.core)
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: try await cloudRecords(of: SessionState.Seed(spaces: [.blank(number: 1)]))
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: device.core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )
        await controller.start()

        await controller.resolveUsingThisDevice()

        XCTAssertEqual(device.store.sessionSeed, local)
        let journal = try device.storedJournal()
        XCTAssertEqual(journal.pending.count, journal.records.count)
        XCTAssertTrue(journal.records.allSatisfy { journal.pending.contains($0.reference) })
        let transport = try device.core.query(CloudTransport())
        XCTAssertFalse(transport.awaitsAccountDecision)
        XCTAssertTrue(transport.overwritesCloud)
        XCTAssertNil(controller.conflict)
        // The staged overwrite waits for the transport, which this test never lets upload.
        XCTAssertEqual(controller.phase, .waitingToUpload)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testDisposableSeedIsReplacedBeforeTransportStarts() async throws {
        let device = try await syncedDevice(.firstInstall)
        let cloudSession = SessionState.Seed(spaces: [.blank(number: 1)])
        let cloud = try await cloudRecords(of: cloudSession)
        try device.core.transport(
            OpenCloudTransport(recordSchema: BrowserCloudRecordCodec.currentSchemaVersion, legacy: nil))
        try device.core.transport(SaveCloudEngineState(serialization: Data([1])))
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            snapshot: cloud
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: device.core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )
        XCTAssertTrue(device.core.state.syncsDisposableSeed)

        await controller.start()

        XCTAssertFalse(device.core.state.syncsDisposableSeed)
        XCTAssertEqual(device.store.spaceModels.map(\.id), cloudSession.spaces.map(\.id))
        XCTAssertNil(
            try device.core.query(CloudTransport()).engineState, "The transport starts over with the cloud's content")
        XCTAssertEqual(controller.observedCloudRecordCount, cloud.count)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testAccountChangeDiscardsTheTransportAndRestartsAgainstTheCurrentAccount() async throws {
        let core = CrestCore()
        let preferences = TestBrowserCloudSyncPreferences()
        let remote = TestBrowserCloudSyncRemoteService(accountState: .available)
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: core,
            configuration: testConfiguration,
            preferences: preferences,
            remoteService: remote,
            transportFactory: factory
        )
        await controller.start()
        let firstTransport = try XCTUnwrap(factory.transports.first)

        await firstTransport.emit(.accountChanged)
        for _ in 0..<100
        where factory.transports.count < 2 || controller.phase != .ready {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(factory.transports.count, 2)
        XCTAssertEqual(controller.accountState, .available)
        XCTAssertEqual(controller.phase, .ready)
    }

    /// A disable that lands while `start` is suspended used to be overtaken: the
    /// resumed launch built a transport with automatic sync on and reported Ready
    /// while the interface said Off.
    func testDisablingSyncMidLaunchLeavesNoLiveTransport() async throws {
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            suspendsAccountState: true
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: remote,
            transportFactory: factory
        )
        let launch = Task { await controller.start() }
        for _ in 0..<200 where !(await remote.isSuspendedForTesting) {
            await Task.yield()
        }

        controller.isEnabled = false
        await remote.release()
        await launch.value
        for _ in 0..<100 where controller.phase != .disabled {
            await Task.yield()
        }

        XCTAssertTrue(factory.transports.isEmpty)
        XCTAssertEqual(controller.phase, .disabled)
        XCTAssertNil(controller.lastSuccessAt)
    }

    /// Nothing observed `CKAccountChanged`, so a device that was signed out at
    /// launch stayed dormant until the next launch or a manual Sync Now.
    func testAnAccountChangeNotificationRestartsSyncOnItsOwn() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("BrowserCloudSyncControllerTests.accountChanged")
        let factory = TestBrowserCloudSyncTransportFactory()
        let remote = TestBrowserCloudSyncRemoteService(accountState: .noAccount)
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: remote,
            transportFactory: factory,
            retryDelay: .seconds(600)
        )
        controller.observeAccountChanges(named: name, center: center)
        await controller.start()
        XCTAssertEqual(controller.phase, .waitingForAccount)
        XCTAssertTrue(factory.transports.isEmpty)

        await remote.signIn()
        center.post(name: name, object: nil)
        for _ in 0..<300 where controller.phase != .ready {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testATransientLaunchFailureRetriesWithoutAnotherLaunch() async throws {
        let remote = TestBrowserCloudSyncRemoteService(
            accountState: .available,
            initialFailures: 1
        )
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: remote,
            transportFactory: factory,
            retryDelay: .milliseconds(1)
        )

        await controller.start()
        XCTAssertNotEqual(controller.phase, .ready)

        for _ in 0..<300 where controller.phase != .ready {
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    /// iCloud can leave an account check unanswered for minutes. The check
    /// fails at its deadline, so the start ends as Needs attention instead of
    /// Checking forever, and the retry that follows reaches the account; the
    /// first check's late answer changes nothing.
    func testAnUnansweredAccountCheckFailsAtItsDeadlineAndTheRetryReachesTheAccount() async throws {
        let remote = TestBrowserCloudSyncRemoteService(accountState: .available, unansweredAccountChecks: 1)
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: CrestCore(),
            configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: remote,
            transportFactory: factory,
            retryDelay: .milliseconds(1),
            accountCheckDeadline: .milliseconds(50)
        )

        await controller.start()

        XCTAssertEqual(controller.phase, .failed)
        XCTAssertEqual(controller.errorDescription, String(describing: BrowserCloudSyncError.accountCheckUnanswered))
        XCTAssertTrue(factory.transports.isEmpty)
        for _ in 0..<300 where controller.phase != .ready {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)

        await remote.answerHeldAccountChecks()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(factory.transports.count, 1)
    }

    func testPullUsesFreshSnapshotTransportAndReportsItsCount() async throws {
        let device = try await syncedDevice()
        let local = device.store.sessionSeed
        let factory = TestBrowserCloudSyncTransportFactory()
        let controller = BrowserCloudSyncController(
            core: device.core, configuration: testConfiguration,
            preferences: TestBrowserCloudSyncPreferences(),
            remoteService: TestBrowserCloudSyncRemoteService(accountState: .available),
            transportFactory: factory
        )
        await controller.start()
        await controller.pullFromICloud()

        let transport = try XCTUnwrap(factory.transports.first)
        let pulls = await transport.pullCount
        XCTAssertEqual(pulls, 1)
        XCTAssertEqual(controller.lastFetchedRecordCount, 4)
        XCTAssertEqual(controller.observedCloudRecordCount, 4)
        XCTAssertNotNil(controller.lastSuccessAt)
        XCTAssertEqual(device.store.sessionSeed, local)

        controller.isEnabled = false
        for _ in 0..<100 where await transport.stopCount == 0 { await Task.yield() }
        await transport.emit(.fetched(recordCount: 99))
        await transport.emit(.idle)
        await controller.pullFromICloud()
        let pullsAfterStop = await transport.pullCount
        XCTAssertEqual(pullsAfterStop, 1)
        XCTAssertEqual(controller.phase, .disabled)
        XCTAssertEqual(controller.lastFetchedRecordCount, 4)
    }

    private var testConfiguration: BrowserCloudSyncConfiguration {
        BrowserCloudSyncConfiguration(containerIdentifier: "iCloud.com.pauldavis.crest")
    }

    /// A device whose file holds `session`, its launch staged: the core the
    /// controller reads and tells.
    private func syncedDevice(_ session: SessionState.Seed = .preview) async throws -> BrowserStoredSessionHarness {
        let device = try BrowserStoredSessionHarness(seed: session)
        await device.store.flushPendingSyncPersistence()
        return device
    }

    /// What another device holding `session` keeps in iCloud.
    /// `core`, with its transport waiting for the person's account decision.
    private func awaitingAccountDecision(_ core: CrestCore) throws -> CrestCore {
        try core.transport(OpenCloudTransport(recordSchema: BrowserCloudRecordCodec.currentSchemaVersion, legacy: nil))
        try core.transport(ObserveCloudAccountChange(transition: .switchAccounts))
        return core
    }

    private func cloudRecords(of session: SessionState.Seed) async throws -> [SyncRecord] {
        let other = try BrowserStoredSessionHarness(
            seed: session, syncDeviceID: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!)
        return try await other.pendingRecords()
    }
}

@MainActor
private final class TestBrowserCloudSyncPreferences: BrowserCloudSyncPreferences {
    var storedIsEnabled: Bool?

    init(storedIsEnabled: Bool? = nil) {
        self.storedIsEnabled = storedIsEnabled
    }

    func loadIsEnabled() -> Bool? { storedIsEnabled }

    func saveIsEnabled(_ isEnabled: Bool) {
        storedIsEnabled = isEnabled
    }
}

private actor TestBrowserCloudSyncRemoteService: BrowserCloudSyncRemoteService {
    enum TestFailure: Error {
        case unavailable
    }

    private let hasEntitlement: Bool
    private var state: CloudAccountState
    private let snapshot: [SyncRecord]
    private let suspendsAccountState: Bool
    private var initialFailures: Int
    private var unansweredAccountChecks: Int
    private var isSuspended = false
    private var wasReleased = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var heldAccountChecks: [CheckedContinuation<Void, Never>] = []

    var isSuspendedForTesting: Bool { isSuspended }

    init(
        hasEntitlement: Bool = true,
        accountState: CloudAccountState,
        snapshot: [SyncRecord] = [],
        suspendsAccountState: Bool = false,
        initialFailures: Int = 0,
        unansweredAccountChecks: Int = 0
    ) {
        self.hasEntitlement = hasEntitlement
        state = accountState
        self.snapshot = snapshot
        self.suspendsAccountState = suspendsAccountState
        self.initialFailures = initialFailures
        self.unansweredAccountChecks = unansweredAccountChecks
    }

    func hasRequiredEntitlement() async -> Bool { hasEntitlement }

    func accountState() async throws -> CloudAccountState {
        if unansweredAccountChecks > 0 {
            unansweredAccountChecks -= 1
            await withCheckedContinuation { heldAccountChecks.append($0) }
        }
        if suspendsAccountState, !wasReleased {
            isSuspended = true
            await withCheckedContinuation { releaseWaiters.append($0) }
            isSuspended = false
        }
        if initialFailures > 0 {
            initialFailures -= 1
            throw TestFailure.unavailable
        }
        return state
    }

    func loadSnapshot() async throws -> [SyncRecord] { snapshot }

    func release() {
        wasReleased = true
        let waiters = releaseWaiters
        releaseWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func signIn() {
        state = .available
    }

    /// Answers the account checks held unanswered, late.
    func answerHeldAccountChecks() {
        let held = heldAccountChecks
        heldAccountChecks = []
        for check in held {
            check.resume()
        }
    }

    nonisolated func message(for error: any Error) -> String {
        String(describing: error)
    }
}

@MainActor
private final class TestBrowserCloudSyncTransportFactory: BrowserCloudSyncTransportFactory {
    private(set) var transports: [TestBrowserCloudSyncTransport] = []
    private let syncFailure: (any Error)?
    private let suspendsPull: Bool

    init(syncFailure: (any Error)? = nil, suspendsPull: Bool = false) {
        self.syncFailure = syncFailure
        self.suspendsPull = suspendsPull
    }

    func makeTransport(
        statusHandler: @escaping @Sendable (BrowserCloudSyncStatus) async -> Void,
        activityHandler: @escaping @Sendable (BrowserCloudSyncActivity) async -> Void
    ) throws -> any BrowserCloudSyncTransport {
        let transport = TestBrowserCloudSyncTransport(
            statusHandler: statusHandler,
            activityHandler: activityHandler,
            syncFailure: syncFailure,
            suspendsPull: suspendsPull
        )
        transports.append(transport)
        return transport
    }
}

private actor TestBrowserCloudSyncTransport: BrowserCloudSyncTransport {
    private(set) var startCount = 0
    private(set) var syncCount = 0
    private(set) var notifyCount = 0
    private(set) var pullCount = 0
    private(set) var stopCount = 0
    private let suspendsPull: Bool
    private var pullWaiter: CheckedContinuation<Void, Never>?
    private let statusHandler: @Sendable (BrowserCloudSyncStatus) async -> Void
    private let activityHandler: @Sendable (BrowserCloudSyncActivity) async -> Void
    private let syncFailure: (any Error)?

    init(
        statusHandler: @escaping @Sendable (BrowserCloudSyncStatus) async -> Void,
        activityHandler: @escaping @Sendable (BrowserCloudSyncActivity) async -> Void,
        syncFailure: (any Error)? = nil,
        suspendsPull: Bool = false
    ) {
        self.statusHandler = statusHandler
        self.activityHandler = activityHandler
        self.syncFailure = syncFailure
        self.suspendsPull = suspendsPull
    }

    func start() async {
        startCount += 1
        await statusHandler(.idle)
    }

    func syncNow() async throws {
        syncCount += 1
        await statusHandler(.syncing)
        if let syncFailure {
            await statusHandler(.failed(String(describing: syncFailure)))
            throw syncFailure
        }
        await statusHandler(.idle)
    }

    func stop() async {
        stopCount += 1
        pullWaiter?.resume()
        pullWaiter = nil
    }

    func pullFromICloud() async throws -> Int {
        pullCount += 1
        if suspendsPull { await withCheckedContinuation { pullWaiter = $0 } }
        if stopCount > 0 { throw CancellationError() }
        if let syncFailure { throw syncFailure }
        return 4
    }

    func notifyLocalChanges() async {
        notifyCount += 1
    }

    func emit(_ activity: BrowserCloudSyncActivity) async {
        await activityHandler(activity)
    }

    func emit(_ status: BrowserCloudSyncStatus) async {
        await statusHandler(status)
    }
}
