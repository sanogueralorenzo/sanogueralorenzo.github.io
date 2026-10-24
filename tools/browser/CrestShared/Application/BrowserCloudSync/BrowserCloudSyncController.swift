import Foundation
import Observation

/// Takes the steps the core decides for iCloud sync on this device, and shows
/// the status it answers. The core decides when sync starts, what a start
/// checks and in which order, when the first launch takes the cloud's
/// content, when an account change waits for the person and what their choice
/// applies, when a sync or a pull counts as a success, and when a failed
/// launch is retried. This side asks CloudKit for the entitlement, the account
/// and the cloud's records, runs the transport, and reports what each step
/// came to, reporting an account check iCloud leaves unanswered past its
/// deadline as failed; it never reads the journal itself.
@Observable
@MainActor
final class BrowserCloudSyncController {
    // MARK: - Variables

    let containerIdentifier: String?

    /// iCloud sync's status, as the core last answered it.
    private(set) var status: CloudSyncStatus

    var isEnabled: Bool {
        get { status.isEnabled }
        set {
            guard newValue != status.isEnabled else { return }
            preferences.saveIsEnabled(newValue)
            let steps = advance(SetCloudSyncEnabled(isEnabled: newValue))
            Task { await take(steps) }
        }
    }

    var accountState: CloudAccountState { status.account }

    var phase: CloudSyncPhase { status.phase }

    var lastAttemptAt: Date? { status.lastAttemptAt }
    var lastSuccessAt: Date? { status.lastSuccessAt }
    var lastFetchedRecordCount: Int { status.lastFetchedRecords }
    var lastUploadedRecordCount: Int { status.lastUploadedRecords }
    var observedCloudRecordCount: Int? { status.observedCloudRecords }
    var skippedRecordCount: Int { status.skippedRecords }
    var requiresAppUpdate: Bool { status.requiresAppUpdate }
    var cloudDataWasRemoved: Bool { status.cloudDataRemoved }
    var conflict: BrowserCloudSyncConflictSummary? { status.conflict.map(BrowserCloudSyncConflictSummary.init) }

    /// What the error line says: a failure in the platform's own words, or
    /// the words for the reason the core found, which for this device's
    /// unsaved changes are what the platform knows of them.
    var errorDescription: String? {
        guard let problem = status.problem else { return status.failureMessage }
        guard problem.reportsError else { return nil }
        return problem.message.map { String(localized: $0) } ?? localErrorDescription
    }

    /// How many records the stored session's journal holds, as the core last
    /// published it.
    var localRecordCount: Int { core.state.syncJournal?.records ?? 0 }

    /// How many of them wait to upload, as the core last published it.
    var pendingUploadCount: Int { core.state.syncJournal?.pendingRecords ?? 0 }

    /// Why this device's changes cannot reach sync: the core could not stage
    /// the latest edits, or could not save them.
    var localErrorDescription: String? {
        core.state.syncStagingFailure.map { String(localized: $0.title) } ?? core.state.storageFailureDescription
    }

    var diagnosticsReport: String {
        BrowserCloudSyncDiagnostics(
            containerIdentifier: containerIdentifier,
            isEnabled: isEnabled,
            accountState: accountState,
            phase: phase,
            localRecordCount: localRecordCount,
            pendingUploadCount: pendingUploadCount,
            observedCloudRecordCount: observedCloudRecordCount,
            lastAttemptAt: lastAttemptAt,
            lastSuccessAt: lastSuccessAt,
            lastFetchedRecordCount: lastFetchedRecordCount,
            lastUploadedRecordCount: lastUploadedRecordCount,
            hasError: errorDescription != nil || localErrorDescription != nil,
            requiresReconciliation: conflict != nil,
            skippedRecordCount: skippedRecordCount,
            requiresAppUpdate: requiresAppUpdate,
            cloudDataWasRemoved: cloudDataWasRemoved
        ).report
    }

    @ObservationIgnored private let core: CrestCore
    @ObservationIgnored private let preferences: any BrowserCloudSyncPreferences
    /// Where an installed release kept the transport's state, which the core
    /// adopts the first time the transport opens.
    @ObservationIgnored private let legacyState: BrowserLegacyCloudSyncState?
    @ObservationIgnored private let remoteService: (any BrowserCloudSyncRemoteService)?
    @ObservationIgnored private let transportFactory: (any BrowserCloudSyncTransportFactory)?
    @ObservationIgnored private let retryDelay: Duration
    /// How long an account check waits on iCloud before the start fails and
    /// the core retries it.
    @ObservationIgnored private let accountCheckDeadline: Duration
    @ObservationIgnored private var transport: (any BrowserCloudSyncTransport)?
    /// The cloud's records a comparison loaded, which the device takes when
    /// it holds nothing.
    @ObservationIgnored private var comparedRecords: [SyncRecord] = []
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var accountObservation: (any NSObjectProtocol)?
    /// Whether the core opened the transport's state in this process.
    @ObservationIgnored private var isTransportStateOpen = false

    // MARK: - Initializers

    init(
        core: CrestCore,
        configuration: BrowserCloudSyncConfiguration?,
        preferences: any BrowserCloudSyncPreferences,
        legacyState: BrowserLegacyCloudSyncState? = nil,
        remoteService: (any BrowserCloudSyncRemoteService)?,
        transportFactory: (any BrowserCloudSyncTransportFactory)?,
        retryDelay: Duration = .seconds(30),
        accountCheckDeadline: Duration = .seconds(10)
    ) {
        self.core = core
        self.preferences = preferences
        self.legacyState = legacyState
        self.remoteService = remoteService
        self.transportFactory = transportFactory
        self.retryDelay = retryDelay
        self.accountCheckDeadline = accountCheckDeadline
        containerIdentifier = configuration?.containerIdentifier
        let configure = ConfigureCloudSync(
            isEnabled: preferences.loadIsEnabled() ?? true,
            canReachCloud: configuration != nil && remoteService != nil && transportFactory != nil)
        var answered: CloudSyncStatus?
        for case .cloudSyncAdvanced(let advanced) in (try? core.send(configure)) ?? [] { answered = advanced.status }
        guard let answered else { preconditionFailure("The core answered no iCloud sync status.") }
        status = answered
    }

    // MARK: - Actions - Requests

    /// Brings sync up against the account that is signed in right now.
    func start() async {
        await run(StartCloudSync())
    }

    func syncNow() async {
        await run(RequestCloudSync())
    }

    func localChangesDidStage() async {
        await run(NotifyCloudLocalChanges())
    }

    /// Called only after the settings confirmation. A full pull merges content;
    /// it never chooses either side as an authoritative replacement.
    func pullFromICloud() async {
        await run(RequestCloudPull())
    }

    func resolveUsingThisDevice() async {
        await run(ChooseCloudCopy(usesCloud: false))
    }

    func resolveUsingICloud() async {
        await run(ChooseCloudCopy(usesCloud: true))
    }

    /// Watches for iCloud sign-in, sign-out, and account switches.
    func observeAccountChanges(
        named name: Notification.Name,
        center: NotificationCenter = .default
    ) {
        guard accountObservation == nil else { return }
        accountObservation = center.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.accountAvailabilityDidChange()
            }
        }
    }

    /// Starts sync again against whichever account is signed in now.
    func accountAvailabilityDidChange() async {
        await run(ObserveCloudAccountAvailability())
    }

    // MARK: - Actions - Steps

    /// Tells the core `intent` and takes the steps it answers.
    private func run(_ intent: some CloudSyncControlIntent) async {
        await take(advance(intent))
    }

    /// Takes `steps` in order; the steps a step's report leads to come
    /// before the ones after it.
    private func take(_ steps: [CloudSyncStep]) async {
        var pending = steps
        while !pending.isEmpty {
            let step = pending.removeFirst()
            pending.insert(contentsOf: await step.kind.take(step, on: self), at: 0)
        }
    }

    /// Runs a step's work and reports what it came to, or the failure with
    /// the cloud records a snapshot counted before it.
    private func reporting<Report: CloudSyncControlIntent>(
        _ step: CloudSyncStep, _ work: (inout Int?) async throws -> Report
    ) async -> [CloudSyncStep] {
        var observed: Int?
        do {
            let report = try await work(&observed)
            return advance(report)
        } catch {
            return failed(step, error, observed: observed)
        }
    }

    private func failed(_ step: CloudSyncStep, _ error: any Error, observed: Int?) -> [CloudSyncStep] {
        let message = remoteService?.message(for: error) ?? String(describing: error)
        return advance(
            CloudStepFailed(attempt: step.attempt, step: step.kind, message: message, observedCloudRecords: observed))
    }

    private func report(_ status: BrowserCloudSyncStatus, attempt: Int64) async {
        let (report, message): (CloudTransportReport, String?) =
            switch status {
            case .stopped: (.stopped, nil)
            case .syncing: (.syncing, nil)
            case .idle: (.idle, nil)
            case .pausedForAccountConfirmation: (.pausedForAccountConfirmation, nil)
            case .failed(let message): (.failed, message)
            }
        await run(
            CloudTransportReported(
                attempt: attempt, report: report, message: message, recordCount: 0, requiresAppUpdate: false))
    }

    private func report(_ activity: BrowserCloudSyncActivity, attempt: Int64) async {
        let (report, count, needsUpdate): (CloudTransportReport, Int, Bool) =
            switch activity {
            case .fetched(let count): (.fetched, count, false)
            case .uploaded(let count): (.uploaded, count, false)
            case .accountChanged: (.accountChanged, 0, false)
            case .skippedRecords(let count, let needsUpdate): (.skippedRecords, count, needsUpdate)
            case .cloudDataRemoved: (.cloudDataRemoved, 0, false)
            }
        await run(
            CloudTransportReported(
                attempt: attempt, report: report, message: nil, recordCount: count, requiresAppUpdate: needsUpdate))
    }

    // MARK: - Actions - Core

    /// Tells the core `intent`, keeps the status it answered, and answers the
    /// steps to take.
    private func advance(_ intent: some CloudSyncControlIntent) -> [CloudSyncStep] {
        guard let changes = try? core.send(intent) else { return [] }
        for case .cloudSyncAdvanced(let advanced) in changes {
            status = advanced.status
            return advanced.steps
        }
        return []
    }

    private func remote() throws -> any BrowserCloudSyncRemoteService {
        guard let remoteService else { throw BrowserCloudSyncError.remoteChangeNotApplied("No remote service.") }
        return remoteService
    }

    /// Has the core open the transport's state under the record schema this
    /// build reads, adopting the state an installed release kept the first
    /// time. Once per process.
    private func openTransportState() async throws {
        guard !isTransportStateOpen else { return }
        let legacy = try core.query(CloudTransport()).isAdopted ? nil : legacyState?.read()
        let core = core
        let open = OpenCloudTransport(recordSchema: BrowserCloudRecordCodec.currentSchemaVersion, legacy: legacy)
        try await Task.detached(priority: .utility) { _ = try core.transport(open) }.value
        isTransportStateOpen = true
    }

    /// How the stored session's journal compares with `cloud`, the cloud's
    /// records, once every stage the core queued has settled. The core
    /// compares them off the main thread.
    private func compare(with cloud: [SyncRecord]) async throws -> CloudContentComparison {
        let core = core
        return try await Task.detached(priority: .utility) {
            await core.settleSync()
            return try core.query(CloudComparison(cloud: cloud))
        }.value
    }

    /// Sends the core the person's choice, or what the first launch takes from
    /// the cloud, off the main thread. What it changed reaches the windows
    /// through the core's wake.
    private func deliver(_ intent: some CloudSyncIntent) async throws {
        let core = core
        try await Task.detached(priority: .utility) { _ = try core.deliver(intent) }.value
    }
}

// MARK: - CloudSyncStepPerformer

extension BrowserCloudSyncController: CloudSyncStepPerformer {
    func checkEntitlement(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        let granted = await remoteService?.hasRequiredEntitlement() ?? false
        return advance(CloudEntitlementChecked(attempt: step.attempt, granted: granted))
    }

    func checkAccount(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        await reporting(step) { _ in
            try await self.openTransportState()
            let check = BrowserCloudAccountCheck(remote: try self.remote(), deadline: self.accountCheckDeadline)
            let state = try await check.state()
            return CloudAccountChecked(attempt: step.attempt, state: state)
        }
    }

    func replaceSeed(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        await reporting(step) { observed in
            let records = try await self.remote().loadSnapshot()
            observed = records.count
            try await self.deliver(ReplaceSeedWithCloudRecords(records: records))
            // The device's first search catalog waited for the seed to give way
            // and now takes the default the cloud's Spaces follow.
            BrowserSearchCatalog.restore(into: self.core)
            return CloudSeedReplaced(attempt: step.attempt, cloudRecords: records.count)
        }
    }

    func compareContent(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        await reporting(step) { observed in
            let records = try await self.remote().loadSnapshot()
            observed = records.count
            self.comparedRecords = records
            let comparison = try await self.compare(with: records)
            return CloudContentCompared(attempt: step.attempt, cloudRecords: records.count, comparison: comparison)
        }
    }

    func takeCloudContent(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        await reporting(step) { _ in
            let records = self.comparedRecords
            self.comparedRecords = []
            try await self.deliver(ReplaceWithCloudRecords(records: records))
            return CloudContentTaken(attempt: step.attempt)
        }
    }

    func applyChosenCopy(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        await reporting(step) { observed in
            let records = try await self.remote().loadSnapshot()
            observed = records.count
            if step.usesCloud {
                try await self.deliver(ReplaceWithCloudRecords(records: records))
            } else {
                try await self.deliver(OverwriteCloud(records: records))
            }
            return CloudCopyApplied(attempt: step.attempt, usesCloud: step.usesCloud, cloudRecords: records.count)
        }
    }

    /// Creates and starts the transport, whose reports name the attempt it
    /// started for. A transport started for a start that is no longer
    /// current is stopped again.
    func startTransport(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        let attempt = step.attempt
        let created: any BrowserCloudSyncTransport
        do {
            guard let transportFactory else { throw BrowserCloudSyncError.remoteChangeNotApplied("No transport.") }
            created = try transportFactory.makeTransport(
                statusHandler: { [weak self] status in await self?.report(status, attempt: attempt) },
                activityHandler: { [weak self] activity in await self?.report(activity, attempt: attempt) })
        } catch {
            return failed(step, error, observed: nil)
        }
        transport = created
        await created.start()
        let next = advance(CloudTransportStarted(attempt: attempt))
        if next.contains(where: { $0.kind == .discardStartedTransport }) { await created.stop() }
        return next.filter { $0.kind != .discardStartedTransport }
    }

    /// The start step that answers it consumes this step, stopping the
    /// transport it just started, so it never reaches the performer alone.
    func discardStartedTransport(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        []
    }

    func stopTransport(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        let previous = transport
        transport = nil
        await previous?.stop()
        return []
    }

    func syncTransport(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        await reporting(step) { _ in
            try await self.transport?.syncNow()
            return CloudTransportSynced(attempt: step.attempt, localChangesUnsaved: self.localErrorDescription != nil)
        }
    }

    func pullTransport(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        await reporting(step) { _ in
            let count = try await self.transport?.pullFromICloud() ?? 0
            return CloudTransportPulled(
                attempt: step.attempt, cloudRecords: count, localChangesUnsaved: self.localErrorDescription != nil)
        }
    }

    func notifyTransport(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        await transport?.notifyLocalChanges()
        return []
    }

    func scheduleRetry(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        let delay = retryDelay
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.run(RetryCloudSync())
        }
        return []
    }

    func cancelRetry(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        retryTask?.cancel()
        retryTask = nil
        return []
    }

    func restartAfterAccountChange(_ step: CloudSyncStep) async -> [CloudSyncStep] {
        Task { [weak self] in await self?.run(RestartCloudSyncAfterAccountChange()) }
        return []
    }
}
