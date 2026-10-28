import CloudKit
import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCloudSyncControllerTests: XCTestCase {
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

    private var testConfiguration: BrowserCloudSyncConfiguration {
        BrowserCloudSyncConfiguration(containerIdentifier: "iCloud.com.pauldavis.crest")
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
