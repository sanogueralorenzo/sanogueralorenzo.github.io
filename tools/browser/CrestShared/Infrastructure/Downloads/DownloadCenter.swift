import Foundation
import Observation
import os

/// Crest's downloads for one browsing mode: the core's download records, the
/// feedback they present, and native data saves. Every record change is an
/// intent sent to the core; engines report their own downloads to the core,
/// which records them and hands the person's row actions back to the engine.
@Observable
@MainActor
final class BrowserDownloadCenter: NSObject {
    // MARK: - Types

    /// Asks the person to approve a risky download: its assessment, source,
    /// Space name and profile.
    typealias RiskApprovalHandler =
        @MainActor (
            DownloadRiskAssessment,
            URL?,
            String,
            UUID
        ) async -> Bool

    typealias DownloadDestinationChooser =
        @MainActor (
            String,
            UUID,
            Bool
        ) async -> any BrowserPlatformDownloadResolution

    // MARK: - Variables

    private static let logger = Logger(subsystem: "com.pauldavis.crest", category: "Downloads")

    /// The core whose read model holds the download records. Views observe
    /// its records directly.
    let core: CrestCore
    private(set) var feedbackEvents: [BrowserDownloadFeedbackEvent] = []

    var items: [DownloadState] {
        core.state.downloads
    }

    @ObservationIgnored let permissionCenter: BrowserSitePermissionCenter
    @ObservationIgnored let approveRiskyDownload: RiskApprovalHandler
    @ObservationIgnored let resolveDownloadDestination: DownloadDestinationChooser
    @ObservationIgnored private var feedbackExpirationTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var dataSaveAssignments: [UUID: BrowserSpaceRuntimeAssignment] = [:]
    @ObservationIgnored private var lastRetentionSweepAt: Date?

    // MARK: - Initializers

    init(
        core: CrestCore = CrestCore(),
        approveRiskyDownload: @escaping RiskApprovalHandler = { _, _, _, _ in false },
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
        resolveDownloadDestination:
            @escaping DownloadDestinationChooser = {
                suggestedFilename,
                spaceID,
                forcesPrompt in
                await BrowserPlatformDownloadDirectory.resolve(
                    suggestedFilename: suggestedFilename,
                    spaceID: spaceID,
                    forcesPrompt: forcesPrompt
                )
            }
    ) {
        self.core = core
        self.approveRiskyDownload = approveRiskyDownload
        self.permissionCenter = permissionCenter
        self.resolveDownloadDestination = resolveDownloadDestination
        super.init()
    }

    // MARK: - Actions - Records

    func items(for profileID: UUID) -> [DownloadState] {
        items.filter { $0.profileID == profileID }
    }

    func unacknowledgedItems(for profileID: UUID) -> [DownloadState] {
        items.filter { $0.profileID == profileID && !$0.isAcknowledged }
    }

    func item(_ itemID: UUID) -> DownloadState? {
        items.first { $0.id == itemID }
    }

    /// Sends one download intent. A refused intent changes nothing; the rule
    /// it broke is logged, since it means an engine reported something the
    /// core cannot record.
    func send(_ intent: some Intent) {
        do {
            try core.send(intent)
        } catch {
            Self.logger.error(
                "The core refused \(String(describing: type(of: intent)), privacy: .public): \(DiagnosticLog.describe(error), privacy: .public)"
            )
        }
    }

    /// Begins a new record and returns its identity.
    func begin(profileID: UUID, filename: String, createdAt: Date = .now, isAcknowledged: Bool = false) -> UUID {
        let itemID = UUID()
        send(
            BeginDownload(
                downloadID: itemID, profileID: profileID, filename: filename, createdAt: createdAt,
                isAcknowledged: isAcknowledged))
        return itemID
    }

    /// The destination names the file, so the record's filename follows it.
    func setDestination(_ destination: URL, for itemID: UUID) {
        send(
            SetDownloadDestination(
                downloadID: itemID, destination: destination.absoluteString, filename: destination.lastPathComponent))
    }

    /// The core's risk verdict for a download. A download the core cannot
    /// judge asks the person first rather than passing as safe.
    func riskVerdict(suggestedFilename: String, mimeType: String?, isUserInitiated: Bool) -> DownloadRiskVerdict {
        let facts = DownloadRiskFacts(suggestedFilename: suggestedFilename, mimeType: mimeType)
        do {
            return try core.query(DownloadRisk(facts: facts, isUserInitiated: isUserInitiated))
        } catch {
            return DownloadRiskVerdict(
                assessment: DownloadRiskAssessment(sanitizedFilename: facts.sanitizedFilename, reasons: []),
                requiresConfirmation: true)
        }
    }

    @discardableResult
    func acknowledgeItems(for profileID: UUID) -> Int {
        (try? core.send(AcknowledgeDownloads(profileID: profileID)))?.count ?? 0
    }

    /// Removes only Crest's terminal download records, under the retention of
    /// each of `spaces`. Files already written to their destination remain
    /// untouched.
    @discardableResult
    func sweepExpiredRecords(
        in spaces: [SpaceModel],
        now: Date = .now,
        force: Bool = false
    ) -> Bool {
        guard
            force
                || BrowserCurrentTabCleanupSchedule.allowsSweep(
                    lastSweptAt: lastRetentionSweepAt,
                    now: now
                )
        else {
            return false
        }
        lastRetentionSweepAt = now
        let expiry = ExpireDownloads(
            now: now,
            retentions: spaces.map {
                DownloadRetention(
                    profileID: $0.profileID,
                    lifetime: $0.settings.browsingPreferences.dataRetention.downloads.lifetime)
            })
        _ = try? core.send(expiry)
        return true
    }

    /// Cancels a live download. The core cancels one an engine runs on its
    /// engine too.
    func cancel(_ itemID: UUID) {
        dataSaveAssignments.removeValue(forKey: itemID)
        if item(itemID)?.phase.isLive == true { send(CancelDownload(downloadID: itemID, message: "Canceled.")) }
    }

    func pause(_ itemID: UUID) {
        guard item(itemID)?.canPause == true else { return }
        send(PauseDownload(downloadID: itemID))
    }

    func resume(_ itemID: UUID) {
        guard item(itemID)?.canResume == true else { return }
        send(ResumeDownload(downloadID: itemID))
    }

    /// Clears a record whose download ended. One an engine ran also leaves the
    /// engine's own list.
    func clear(_ itemID: UUID) {
        guard item(itemID)?.phase.isLive != true, dataSaveAssignments[itemID] == nil else { return }
        send(RemoveDownload(downloadID: itemID))
    }

    /// Deletes a Space's records. The core cancels and removes the downloads
    /// its profile's engines still run.
    func deleteRecords(profileID: UUID, spaceID: UUID) {
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
        dataSaveAssignments = dataSaveAssignments.filter { $0.value != assignment }
        send(RemoveProfileDownloads(profileID: profileID))
    }

    /// Retries a download the site's choices blocked, while its Space is
    /// still there to hold it: the core has its engine replay it.
    @discardableResult
    func retryAutomaticDownload(
        _ itemID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        isAssignmentAvailable: @MainActor (BrowserSpaceRuntimeAssignment) -> Bool
    ) -> Bool {
        guard let item = item(itemID), item.profileID == assignment.profileID, item.phase.canRetry,
            isAssignmentAvailable(assignment)
        else { return false }
        send(RestartDownload(downloadID: itemID))
        return true
    }

    // MARK: - Actions - Native data saves

    /// Saves bytes supplied by a trusted native user action, such as WebKit's
    /// PDF toolbar. No network request or automatic-download permission is
    /// involved, but destination consent and file safeguards still apply.
    @discardableResult
    func saveData(
        _ data: Data,
        suggestedFilename: String,
        mimeType: String,
        originatingURL: URL,
        assignment: BrowserSpaceRuntimeAssignment,
        spaceName: String,
        feedbackSource: BrowserDownloadFeedbackSource? = nil
    ) async -> UUID {
        let verdict = riskVerdict(suggestedFilename: suggestedFilename, mimeType: mimeType, isUserInitiated: true)
        let assessment = verdict.assessment
        let itemID = begin(profileID: assignment.profileID, filename: assessment.sanitizedFilename)
        send(AssessDownloadRisk(downloadID: itemID, assessment: assessment))
        dataSaveAssignments[itemID] = assignment
        if let feedbackSource {
            presentFeedback(
                BrowserDownloadFeedbackEvent(
                    id: itemID, profileID: assignment.profileID, spaceID: assignment.spaceID,
                    filename: assessment.sanitizedFilename, source: feedbackSource))
        }
        await finishSavingData(
            data, itemID: itemID, verdict: verdict, originatingURL: originatingURL,
            assignment: assignment, spaceName: spaceName)
        return itemID
    }

    private func finishSavingData(
        _ data: Data,
        itemID: UUID,
        verdict: DownloadRiskVerdict,
        originatingURL: URL,
        assignment: BrowserSpaceRuntimeAssignment,
        spaceName: String
    ) async {
        defer { dataSaveAssignments.removeValue(forKey: itemID) }
        guard dataSaveAssignments[itemID] == assignment else { return }
        let assessment = verdict.assessment
        if verdict.requiresConfirmation {
            let approved = await approveRiskyDownload(assessment, originatingURL, spaceName, assignment.profileID)
            guard dataSaveAssignments[itemID] == assignment else { return }
            guard approved else {
                send(
                    CancelDownload(
                        downloadID: itemID, message: "Canceled before downloading a potentially dangerous file."))
                return
            }
        }
        let resolution = await resolveDownloadDestination(assessment.sanitizedFilename, assignment.spaceID, false)
        // Cancellation or removal of the owning Space can happen while a
        // native panel is open. A late response must never resurrect the save.
        guard dataSaveAssignments[itemID] == assignment else { return }
        resolution.save(data, as: itemID, from: originatingURL, in: self)
    }

    /// Writes `data` to `destination` through Crest's staging folder, with
    /// the quarantine of the page it came from.
    func saveDataToDestination(
        _ data: Data, itemID: UUID, destination: URL, originatingURL: URL
    ) throws {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let stagingDirectory =
            applicationSupport
            .appendingPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
            .appendingPathComponent("Download Staging", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = BrowserDownloadTransfer.stagingURL(
            itemID: itemID, suggestedFilename: destination.lastPathComponent, directory: stagingDirectory)
        defer { try? fileManager.removeItem(at: staging) }
        setDestination(destination, for: itemID)
        try data.write(to: staging, options: .atomic)
        try BrowserDownloadTransfer.finish(
            from: staging, to: destination, quarantine: BrowserDownloadQuarantine(sourceURL: originatingURL))
    }

    // MARK: - Actions - Feedback

    func dismissFeedback(_ eventID: UUID) {
        feedbackEvents.removeAll { $0.id == eventID }
        feedbackExpirationTasks.removeValue(forKey: eventID)?.cancel()
    }

    /// Shows a download leaving where it started. Every window over the page
    /// hears its start, so an event already shown is shown once.
    func presentFeedback(_ event: BrowserDownloadFeedbackEvent) {
        guard !feedbackEvents.contains(where: { $0.id == event.id }) else { return }
        let previousIDs = Set(feedbackEvents.map(\.id))
        feedbackEvents = event.appended(to: feedbackEvents)
        let retainedIDs = Set(feedbackEvents.map(\.id))
        for removedID in previousIDs.subtracting(retainedIDs) {
            feedbackExpirationTasks.removeValue(forKey: removedID)?.cancel()
        }
        feedbackExpirationTasks[event.id]?.cancel()
        feedbackExpirationTasks[event.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: BrowserDownloadFeedbackEvent.lifetime)
            guard !Task.isCancelled else { return }
            self?.dismissFeedback(event.id)
        }
    }
}
