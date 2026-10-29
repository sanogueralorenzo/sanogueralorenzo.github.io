import Foundation

/// One native ledger for web downloads and platform saves. CoreState exposes the
/// same records to every window; transfer identities remain retired after clearing.
@MainActor
final class BrowserNativeDownloads {
    static let maximumItems = 10_000
    private unowned let core: CrestCore
    private var records: [UUID: Tracked] = [:]
    private var waiting: [UUID: Waiting] = [:]
    private var depth = 0
    private var flushing = false
    private var effects: [@MainActor () -> Void] = []

    private final class Tracked {
        weak var binding: WebKitEngineBinding?
        let profileID: UUID
        let id: UUID
        var estimator: DownloadTransferEstimator?
        var isLive = true
        var isBlocked = false
        var lastReport: EngineDownload?
        var approvalToken: String?
        var reasons: [DownloadRiskReason] = []
        var reasonsApproved = false
        var sourceHost: String?
        init(_ report: EngineDownload, _ binding: WebKitEngineBinding) {
            profileID = report.profileID
            id = report.downloadID
            self.binding = binding
        }
    }

    private enum Question {
        case destination, approval
        case risk(EngineDownloadDestinationRequested)
    }
    private struct Waiting {
        let download: Tracked
        let question: Question
    }

    init(core: CrestCore) { self.core = core }

    var items: [DownloadState] {
        get { core.state.downloads }
        set { core.state.downloads = newValue }
    }

    @discardableResult
    func send(_ intent: some DownloadIntent) throws(DownloadLedgerError) -> [UUID] {
        if depth == 0 { core.drain() }
        depth += 1
        defer { finishTurn() }
        return try intent.apply(to: self)
    }

    /// Deliver controls after state commits. Synchronous WebKit callbacks append
    /// work to this same turn rather than entering an unfinished transition.
    private func finishTurn() {
        depth -= 1
        guard depth == 0 else { return }
        guard !flushing else { return }
        flushing = true
        var index = 0
        while index < effects.count {
            let effect = effects[index]
            index += 1
            effect()
        }
        effects.removeAll(keepingCapacity: true)
        flushing = false
    }

    private func updated(_ item: DownloadState) {
        effects.append { [weak core] in core?.downloadsChanged([item]) }
    }

    private func prompt(_ change: any CorePromptChange) {
        effects.append { [weak core] in core?.promptsChanged([change]) }
    }

    private func record(_ intent: some DownloadIntent) { _ = try? send(intent) }

    private func update(
        _ id: UUID, accepting: (DownloadState) -> Bool = { $0.phase.isLive },
        _ transition: (inout DownloadState) -> Void
    ) -> [UUID] {
        guard let index = items.firstIndex(where: { $0.id == id }), accepting(items[index]) else { return [] }
        var item = items[index]
        transition(&item)
        items[index] = item
        updated(item)
        return [id]
    }

    func begin(_ action: BeginDownload) throws(DownloadLedgerError) -> [UUID] {
        let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        guard action.downloadID != zero, action.profileID != zero else { throw .invalidIdentity }
        try DownloadTextField.filename.validate(action.filename)
        guard !items.contains(where: { $0.id == action.downloadID }) else { throw .duplicate }
        guard items.count < Self.maximumItems else { throw .limitReached(Self.maximumItems) }
        let item = DownloadState(
            id: action.downloadID, profileID: action.profileID, createdAt: action.createdAt,
            filename: action.filename, destination: nil, progress: 0, telemetry: .empty,
            phase: .preparing, failure: nil, message: nil, risk: nil,
            isAcknowledged: action.isAcknowledged, canPause: false, canResume: false)
        items.insert(item, at: 0)
        updated(item)
        return [item.id]
    }

    func destination(_ action: SetDownloadDestination) throws(DownloadLedgerError) -> [UUID] {
        try DownloadTextField.destination.validate(action.destination)
        try DownloadTextField.filename.validate(action.filename)
        return update(action.downloadID) {
            $0.destination = action.destination
            $0.filename = action.filename
            $0.phase = .downloading
        }
    }

    func transfer(_ action: RecordDownloadTransfer) throws(DownloadLedgerError) -> [UUID] {
        guard action.telemetry.isValid, action.progress.isFinite else { throw .invalidProgress }
        return update(action.downloadID) {
            $0.telemetry = action.telemetry
            $0.progress = max($0.progress, min(max(action.progress, 0), 1))
        }
    }

    func assess(_ action: AssessDownloadRisk) throws(DownloadLedgerError) -> [UUID] {
        try DownloadTextField.filename.validate(action.assessment.sanitizedFilename)
        return update(action.downloadID) {
            $0.filename = action.assessment.sanitizedFilename
            $0.risk = action.assessment
            if !action.assessment.reasons.isEmpty { $0.phase = .awaitingApproval }
        }
    }

    func awaitApproval(_ id: UUID) -> [UUID] { update(id) { $0.phase = .awaitingApproval } }

    func finish(_ action: FinishDownload) throws(DownloadLedgerError) -> [UUID] {
        guard (action.finalByteCount ?? 0) >= 0 else { throw .invalidProgress }
        return update(action.downloadID) {
            $0.progress = 1
            $0.telemetry = $0.telemetry.stopped(finalByteCount: action.finalByteCount, completed: true)
            $0.phase = .finished
            $0.canPause = false
            $0.canResume = false
        }
    }

    private func stopped(_ item: inout DownloadState, phase: DownloadPhase, message: String?) {
        item.phase = phase
        item.telemetry = item.telemetry.stopped()
        item.failure = nil
        item.message = message
        item.canPause = false
        item.canResume = false
    }

    func cancel(_ action: CancelDownload) throws(DownloadLedgerError) -> [UUID] {
        try DownloadTextField.message.validate(action.message)
        if let tracked = tracking(action.downloadID), tracked.isLive, !tracked.isBlocked {
            effects.append { tracked.binding?.downloads.cancel(tracked.id) }
            end(tracked)
        }
        return update(action.downloadID) { stopped(&$0, phase: .canceled, message: action.message) }
    }

    func fail(_ action: FailDownload) throws(DownloadLedgerError) -> [UUID] {
        if action.message != nil || action.reason == nil {
            try DownloadTextField.message.validate(action.message ?? "")
        }
        return update(
            action.downloadID, accepting: { $0.phase.isLive || $0.phase.canRetry },
            {
                stopped(&$0, phase: .failed, message: action.message)
                $0.failure = action.reason
            })
    }

    func block(_ id: UUID) -> [UUID] { update(id) { stopped(&$0, phase: .blockedAutomaticDownload, message: nil) } }

    func restart(_ id: UUID) -> [UUID] {
        if let tracked = tracking(id), tracked.isLive, tracked.isBlocked {
            tracked.isBlocked = false
            effects.append { tracked.binding?.downloads.approve(tracked.id) }
            tracked.approvalToken = nil
        }
        return update(
            id, accepting: { $0.phase.canRetry },
            {
                $0.destination = nil
                $0.progress = 0
                $0.telemetry = .empty
                $0.phase = .preparing
                $0.failure = nil
                $0.message = nil
                $0.risk = nil
                $0.isAcknowledged = false
                $0.canPause = false
                $0.canResume = false
            })
    }

    func acknowledge(_ profileID: UUID) -> [UUID] {
        let ids = items.filter { $0.profileID == profileID && !$0.isAcknowledged }.map(\.id)
        for id in ids { _ = update(id, accepting: { _ in true }, { $0.isAcknowledged = true }) }
        return ids
    }

    func remove(_ id: UUID) -> [UUID] {
        if let tracked = tracking(id), !tracked.isLive || tracked.isBlocked {
            effects.append { tracked.binding?.downloads.remove(tracked.id) }
            end(tracked)
        }
        let removed = items.contains { $0.id == id }
        items.removeAll { $0.id == id }
        return removed ? [id] : []
    }

    func removeProfile(_ profileID: UUID) -> [UUID] {
        for tracked in records.values where tracked.profileID == profileID {
            if tracked.isLive { effects.append { tracked.binding?.downloads.cancel(tracked.id) } }
            effects.append { tracked.binding?.downloads.remove(tracked.id) }
            end(tracked)
        }
        let ids = items.filter { $0.profileID == profileID }.map(\.id)
        items.removeAll { $0.profileID == profileID }
        return ids
    }

    func expire(_ action: ExpireDownloads) throws(DownloadLedgerError) -> [UUID] {
        var limits: [UUID: TimeInterval] = [:]
        for retention in action.retentions {
            guard (retention.lifetime ?? 0) >= 0 else { throw .invalidRetention }
            if let lifetime = retention.lifetime {
                limits[retention.profileID] = min(limits[retention.profileID] ?? lifetime, lifetime)
            }
        }
        let ids = items.filter { item in
            !item.phase.isLive
                && limits[item.profileID].map { action.now.timeIntervalSince(item.createdAt) > $0 } == true
        }.map(\.id)
        let removed = Set(ids)
        items.removeAll { removed.contains($0.id) }
        return ids
    }

    // WebKit does not offer pause or recovery controls.
    func pause(_ id: UUID) -> [UUID] { [] }
    func resume(_ id: UUID) -> [UUID] { [] }

    private func tracking(_ id: UUID) -> Tracked? { records[id] }

    func isAwaitingDestination(_ promptID: UUID, downloadID: UUID) -> Bool {
        guard let value = waiting[promptID], value.download.id == downloadID, value.download.isLive else {
            return false
        }
        if case .destination = value.question { return true }
        return false
    }

    private func pageSpace(of report: EngineDownload) -> UUID? {
        guard let pageID = report.sourcePageID, let page = core.state.pages[pageID],
            let workspace = core.state.workspaces[page.workspaceID],
            let space = workspace.spaces.model(page.spaceID), space.profileID == report.profileID,
            !workspace.spaceDeletions.contains(where: { $0.spaceID == space.id })
        else { return nil }
        return space.id
    }

    private func space(of report: EngineDownload) -> UUID? {
        if let space = pageSpace(of: report) { return space }
        var owners: [UUID: (WorkspaceModel, SpaceModel)] = [:]
        for workspace in core.state.workspaces.values.sorted(by: { $0.kind.ownsSpaces && !$1.kind.ownsSpaces }) {
            for space in workspace.spaces.models where space.profileID == report.profileID && owners[space.id] == nil {
                owners[space.id] = (workspace, space)
            }
        }
        guard owners.count == 1, let (workspace, space) = owners.values.first,
            !workspace.spaceDeletions.contains(where: { $0.spaceID == space.id })
        else { return nil }
        return space.id
    }

    private func track(_ report: EngineDownload, binding: WebKitEngineBinding) -> Tracked? {
        if let known = records[report.downloadID] { return known.profileID == report.profileID ? known : nil }
        guard space(of: report) != nil else { return nil }
        let tracked = Tracked(report, binding)
        records[report.downloadID] = tracked
        record(
            BeginDownload(
                downloadID: tracked.id, profileID: report.profileID,
                filename: BrowserDownloadDestination.safeFilename(from: report.filename),
                createdAt: report.startedAt, isAcknowledged: report.restored))
        if !report.restored, let pageID = report.sourcePageID,
            pageSpace(of: report) != nil,
            items.contains(where: { $0.id == tracked.id })
        {
            effects.append { [weak core] in
                core?.downloadsStarted([DownloadStarted(downloadID: tracked.id, pageID: pageID)])
            }
        }
        return tracked
    }

    func report(_ event: EngineDownloadChanged, from binding: WebKitEngineBinding) {
        if depth == 0 { core.drain() }
        depth += 1
        defer { finishTurn() }
        let report = event.download
        guard let tracked = track(report, binding: binding) else {
            effects.append { binding.downloads.cancel(report.downloadID) }
            return
        }
        guard tracked.isLive else { return }
        tracked.lastReport = report
        if let path = report.path, !path.isEmpty {
            record(
                SetDownloadDestination(
                    downloadID: tracked.id, destination: URL(fileURLWithPath: path).absoluteString,
                    filename: URL(fileURLWithPath: path).lastPathComponent))
        }
        if let reading = try? DownloadProgress(
            estimator: tracked.estimator, completedUnitCount: report.received,
            totalUnitCount: report.total,
            fractionCompleted: report.total > 0 ? Double(report.received) / Double(report.total) : 0,
            isPaused: report.paused, uptime: ProcessInfo.processInfo.systemUptime
        ).answer() {
            tracked.estimator = reading.estimator
            record(
                RecordDownloadTransfer(downloadID: tracked.id, telemetry: reading.telemetry, progress: reading.progress)
            )
        }
        switch report.state {
        case .preparing, .downloading: settleApproval(tracked)
        case .awaitingApproval: warn(tracked, report)
        case .finished:
            record(FinishDownload(downloadID: tracked.id, finalByteCount: max(report.received, 0)))
            end(tracked)
        case .canceled:
            record(CancelDownload(downloadID: tracked.id, message: "Canceled."))
            end(tracked)
        case .failed:
            let failure: DownloadFailure =
                report.warning.flatMap { warning in DownloadWarning.all.first { $0.engineWarning == warning }?.failure }
                ?? {
                    switch report.interruption {
                    case .network: .network
                    case .server: .server
                    case .noSpace: .noSpace
                    case .fileAccess: .fileAccess
                    default: .interrupted
                    }
                }()
            let message = report.failureDetail.flatMap {
                !$0.isEmpty && $0.utf16.count <= DownloadTextField.message.maximumLength ? $0 : nil
            }
            record(FailDownload(downloadID: tracked.id, reason: failure, message: message))
            end(tracked)
        case .blocked:
            record(BlockAutomaticDownload(downloadID: tracked.id))
            tracked.isBlocked = true
            tracked.approvalToken = report.approvalToken
        }
        _ = update(
            tracked.id,
            accepting: {
                $0.canPause != (report.canPause && !report.paused && report.warning == nil && $0.phase.isTransferring)
                    || $0.canResume != (report.canResume && report.warning == nil && $0.phase.allowsResume)
            },
            {
                $0.canPause = report.canPause && !report.paused && report.warning == nil && $0.phase.isTransferring
                $0.canResume = report.canResume && report.warning == nil && $0.phase.allowsResume
            })
    }

    func report(_ event: EngineDownloadDestinationRequested, from binding: WebKitEngineBinding) {
        if depth == 0 { core.drain() }
        depth += 1
        defer { finishTurn() }
        guard let tracked = track(event.download, binding: binding), tracked.isLive,
            let spaceID = space(of: event.download)
        else {
            effects.append { binding.downloads.settle(promptID: event.promptID, path: nil) }
            return
        }
        tracked.sourceHost = event.sourceHost.flatMap { !$0.isEmpty && $0.utf16.count <= 253 ? $0 : nil }
        let verdict =
            (try? DownloadRisk(facts: event.facts, isUserInitiated: event.userInitiated).answer())
            ?? DownloadRiskVerdict(
                assessment: DownloadRiskAssessment(
                    sanitizedFilename: BrowserDownloadDestination.safeFilename(from: event.facts.suggestedFilename),
                    reasons: []), requiresConfirmation: true)
        record(AssessDownloadRisk(downloadID: tracked.id, assessment: verdict.assessment))
        tracked.reasons = verdict.assessment.reasons
        tracked.reasonsApproved = false
        if verdict.requiresConfirmation {
            let id = UUID()
            waiting[id] = Waiting(download: tracked, question: .risk(event))
            prompt(
                DownloadApprovalAsked(
                    promptID: id, downloadID: tracked.id, spaceID: spaceID,
                    filename: BrowserDownloadDestination.safeFilename(from: event.suggestedFilename),
                    reasons: tracked.reasons, warning: nil, sourceHost: tracked.sourceHost))
        } else {
            askDestination(tracked, event, spaceID)
        }
    }

    private func askDestination(_ tracked: Tracked, _ event: EngineDownloadDestinationRequested, _ spaceID: UUID) {
        waiting[event.promptID] = Waiting(download: tracked, question: .destination)
        prompt(
            DownloadDestinationAsked(
                promptID: event.promptID, downloadID: tracked.id, spaceID: spaceID,
                suggestedFilename: BrowserDownloadDestination.safeFilename(from: event.suggestedFilename),
                forcesPrompt: event.forcesPrompt))
    }

    private func warn(_ tracked: Tracked, _ report: EngineDownload) {
        guard let warning = report.warning.flatMap({ kind in DownloadWarning.all.first { $0.engineWarning == kind } })
        else {
            effects.append { tracked.binding?.downloads.cancel(tracked.id) }
            return
        }
        if tracked.reasonsApproved, tracked.reasons.contains(where: { warning.coveredBy.contains($0) }) {
            guard tracked.approvalToken != report.approvalToken else { return }
            tracked.approvalToken = report.approvalToken
            effects.append { tracked.binding?.downloads.approve(tracked.id) }
            return
        }
        record(AwaitDownloadApproval(downloadID: tracked.id))
        guard tracked.approvalToken != report.approvalToken else { return }
        settleApproval(tracked)
        tracked.approvalToken = report.approvalToken
        let id = UUID()
        waiting[id] = Waiting(download: tracked, question: .approval)
        prompt(
            DownloadApprovalAsked(
                promptID: id, downloadID: tracked.id, spaceID: space(of: report),
                filename: BrowserDownloadDestination.safeFilename(from: report.filename),
                reasons: tracked.reasons, warning: warning, sourceHost: tracked.sourceHost))
    }

    private func settle(_ id: UUID) {
        if waiting.removeValue(forKey: id) != nil { prompt(PromptSettled(promptID: id)) }
    }
    private func end(_ tracked: Tracked) {
        tracked.isLive = false
        for id in waiting.filter({ $0.value.download === tracked }).map(\.key) { settle(id) }
    }
    private func settleApproval(_ tracked: Tracked) {
        tracked.approvalToken = nil
        for (id, value) in waiting where value.download === tracked {
            if case .approval = value.question { settle(id) }
        }
    }

    func answer(_ action: AnswerDownloadDestination) throws(DownloadLedgerError) -> [UUID] {
        guard let value = waiting[action.promptID] else { throw .unknownPrompt(action.promptID) }
        guard case .destination = value.question else { throw .answerMismatch(action.promptID) }
        settle(action.promptID)
        if let path = action.path, !path.isEmpty, value.download.isLive {
            record(
                SetDownloadDestination(
                    downloadID: value.download.id, destination: URL(fileURLWithPath: path).absoluteString,
                    filename: URL(fileURLWithPath: path).lastPathComponent))
        }
        effects.append { [weak tracked = value.download] in
            tracked?.binding?.downloads.settle(promptID: action.promptID, path: action.path)
        }
        return []
    }

    func answer(_ action: AnswerDownloadApproval) throws(DownloadLedgerError) -> [UUID] {
        guard let value = waiting[action.promptID] else { throw .unknownPrompt(action.promptID) }
        guard case .destination = value.question else {
            let tracked = value.download
            settle(action.promptID)
            switch value.question {
            case .risk(let held):
                if action.approved, let spaceID = space(of: held.download) {
                    tracked.reasonsApproved = true
                    askDestination(tracked, held, spaceID)
                } else {
                    effects.append { [weak tracked] in
                        tracked?.binding?.downloads.settle(promptID: held.promptID, path: nil)
                    }
                    record(
                        CancelDownload(
                            downloadID: tracked.id,
                            message: action.approved
                                ? "Canceled." : "Canceled before downloading a potentially dangerous file."))
                    end(tracked)
                }
            case .approval:
                if action.approved {
                    effects.append { tracked.binding?.downloads.approve(tracked.id) }
                } else {
                    effects.append { tracked.binding?.downloads.cancel(tracked.id) }
                    record(CancelDownload(downloadID: tracked.id, message: "Canceled."))
                    end(tracked)
                }
            case .destination: break
            }
            return []
        }
        throw .answerMismatch(action.promptID)
    }
}
