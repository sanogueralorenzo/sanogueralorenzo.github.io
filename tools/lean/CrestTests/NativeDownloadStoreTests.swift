import Foundation
import XCTest

@testable import Crest

@MainActor
final class NativeDownloadStoreTests: XCTestCase {
    private var retainedStores: [BrowserStore] = []
    func testTerminalRecordsIgnoreLateProgressAndClearedWebTransfersStayRetired() throws {
        let (core, binding, profile) = context()
        var report = snapshot(profile: profile)
        binding.report(EngineDownloadChanged(download: report))
        let id = try XCTUnwrap(core.state.downloads.first).id
        report.state = .finished
        report.received = 50
        report.total = 50
        binding.report(EngineDownloadChanged(download: report))
        let finished = try XCTUnwrap(core.state.downloads.first)
        XCTAssertEqual(finished.phase, .finished)
        XCTAssertEqual(finished.telemetry.bytesReceived, 50)
        XCTAssertEqual(finished.telemetry.totalBytes, 50)
        XCTAssertNil(finished.telemetry.bytesPerSecond)
        report.state = .downloading
        report.received = 80
        binding.report(EngineDownloadChanged(download: report))
        XCTAssertEqual(core.state.downloads, [finished])
        try core.send(RemoveDownload(downloadID: id))
        binding.report(EngineDownloadChanged(download: report))
        XCTAssertTrue(core.state.downloads.isEmpty)
    }

    func testLedgerProgressIsMonotonicAndAcknowledgementIsProfileScoped() throws {
        let core = CrestCore()
        let profile = UUID()
        let other = UUID()
        let id = UUID()
        try begin(core, id, profile)
        try begin(core, UUID(), other)
        let telemetry = DownloadTelemetry(
            bytesReceived: 20, totalBytes: 100, bytesPerSecond: 10,
            estimatedTimeRemaining: 8, isPaused: false)
        try core.send(RecordDownloadTransfer(downloadID: id, telemetry: telemetry, progress: 0.8))
        try core.send(RecordDownloadTransfer(downloadID: id, telemetry: telemetry, progress: 0.2))
        XCTAssertEqual(core.state.downloads.last?.progress, 0.8)
        XCTAssertEqual(try core.send(AcknowledgeDownloads(profileID: profile)), [id])
        XCTAssertTrue(try core.send(AcknowledgeDownloads(profileID: profile)).isEmpty)
        XCTAssertFalse(try XCTUnwrap(core.state.downloads.first).isAcknowledged)
        try core.send(CancelDownload(downloadID: id, message: "Canceled."))
        let canceled = try XCTUnwrap(core.state.downloads.last)
        try core.send(SetDownloadDestination(downloadID: id, destination: "file:///tmp/late", filename: "late"))
        try core.send(FinishDownload(downloadID: id, finalByteCount: 100))
        XCTAssertEqual(core.state.downloads.last, canceled)
        XCTAssertNil(canceled.telemetry.bytesPerSecond)
    }

    func testExpiryUsesTheShortestRetentionAndNeverExpiresLiveTransfers() throws {
        let core = CrestCore()
        let profile = UUID()
        let other = UUID()
        let old = UUID()
        let boundary = UUID()
        let live = UUID()
        let foreign = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        try begin(core, old, profile, at: now.addingTimeInterval(-101))
        try begin(core, boundary, profile, at: now.addingTimeInterval(-100))
        try begin(core, live, profile, at: now.addingTimeInterval(-1_000))
        try begin(core, foreign, other, at: now.addingTimeInterval(-1_000))
        for id in [old, boundary, foreign] { try core.send(FinishDownload(downloadID: id, finalByteCount: 10)) }
        try core.send(
            ExpireDownloads(
                now: now,
                retentions: [
                    DownloadRetention(profileID: profile, lifetime: nil),
                    DownloadRetention(profileID: profile, lifetime: 100),
                ]))
        XCTAssertEqual(Set(core.state.downloads.map(\.id)), [boundary, live, foreign])
        try core.send(RemoveProfileDownloads(profileID: profile))
        XCTAssertEqual(core.state.downloads.map(\.id), [foreign])
    }

    func testBlockedRecordsRetryUnderTheirIdentityAndBecomeNewsAgain() throws {
        let core = CrestCore()
        let profile = UUID()
        let id = UUID()
        try begin(core, id, profile)
        try core.send(BlockAutomaticDownload(downloadID: id))
        try core.send(AcknowledgeDownloads(profileID: profile))
        XCTAssertFalse(try XCTUnwrap(core.state.downloads.first).phase.isLive)
        try core.send(RestartDownload(downloadID: id))
        let retried = try XCTUnwrap(core.state.downloads.first)
        XCTAssertEqual(retried.id, id)
        XCTAssertEqual(retried.phase, .preparing)
        XCTAssertFalse(retried.isAcknowledged)
        XCTAssertNil(retried.destination)
        try core.send(FailDownload(downloadID: id, reason: .network, message: nil))
        let failed = try XCTUnwrap(core.state.downloads.first)
        try core.send(RestartDownload(downloadID: id))
        XCTAssertEqual(core.state.downloads.first, failed)
    }

    func testInvalidInputLeavesTheLedgerUnchanged() throws {
        let core = CrestCore()
        let profile = UUID()
        let id = UUID()
        try begin(core, id, profile)
        XCTAssertThrowsError(try begin(core, id, profile)) { XCTAssertEqual($0 as? DownloadLedgerError, .duplicate) }
        XCTAssertThrowsError(try core.send(RecordDownloadTransfer(downloadID: id, telemetry: .empty, progress: .nan)))
        XCTAssertThrowsError(try core.send(FinishDownload(downloadID: id, finalByteCount: -1)))
        XCTAssertThrowsError(try core.send(SetDownloadDestination(downloadID: id, destination: "", filename: "x")))
        XCTAssertThrowsError(
            try core.send(ExpireDownloads(now: .now, retentions: [DownloadRetention(profileID: profile, lifetime: -1)]))
        )
        XCTAssertEqual(core.state.downloads.first?.phase, .preparing)
        XCTAssertEqual(core.state.downloads.first?.progress, 0)
    }

    func testRiskApprovalPrecedesDestinationAndDecliningRetiresTheTransfer() throws {
        let (core, binding, profile) = context()
        let host = Prompts()
        core.followPrompts(host)
        let report = snapshot(profile: profile)
        binding.report(EngineDownloadChanged(download: report))
        let request = destination(report)
        binding.report(request)
        let asked = try XCTUnwrap(host.approvals.first)
        XCTAssertTrue(host.destinations.isEmpty)
        XCTAssertEqual(asked.reasons, [.deceptiveFilename])
        try core.send(AnswerDownloadApproval(promptID: asked.promptID, approved: false))
        XCTAssertEqual(core.state.downloads.first?.phase, .canceled)
        XCTAssertTrue(host.dismissed.contains(asked.promptID))
        binding.report(EngineDownloadChanged(download: report))
        XCTAssertEqual(core.state.downloads.first?.phase, .canceled)
        XCTAssertThrowsError(try core.send(AnswerDownloadApproval(promptID: asked.promptID, approved: true)))
    }

    func testApprovedRiskRequestsDestinationAndDoesNotRepeatAnAlreadyCoveredWarning() throws {
        let (core, binding, profile) = context()
        let host = Prompts()
        core.followPrompts(host)
        var report = snapshot(profile: profile)
        binding.report(EngineDownloadChanged(download: report))
        let request = EngineDownloadDestinationRequested(
            promptID: UUID(), download: report, suggestedFilename: "setup.pkg", forcesPrompt: false,
            facts: DownloadRiskFacts(
                suggestedFilename: "setup.pkg", sanitizedFilename: "setup.pkg", mimeType: nil,
                extensionRunsCode: false, mimeTypeRunsCode: false, typesRelated: nil),
            userInitiated: false, sourceHost: "example.com")
        binding.report(request)
        let approval = try XCTUnwrap(host.approvals.first)
        try core.send(AnswerDownloadApproval(promptID: approval.promptID, approved: true))
        let destination = try XCTUnwrap(host.destinations.first)
        XCTAssertEqual(destination.promptID, request.promptID)
        try core.send(AnswerDownloadDestination(promptID: destination.promptID, path: "/tmp/native-download-test.pkg"))
        XCTAssertEqual(core.state.downloads.first?.filename, "native-download-test.pkg")
        report.state = .awaitingApproval
        report.warning = .dangerousFile
        report.approvalToken = "warning-one"
        binding.report(EngineDownloadChanged(download: report))
        XCTAssertEqual(host.approvals.count, 1)
        XCTAssertEqual(core.state.downloads.first?.phase, .downloading)
        report.state = .finished
        report.warning = nil
        report.received = 512
        binding.report(EngineDownloadChanged(download: report))
        XCTAssertEqual(core.state.downloads.first?.phase, .finished)
        XCTAssertEqual(core.state.downloads.first?.telemetry.bytesReceived, 512)
    }

    func testOrphanReportsCannotCreateRecordsAndProfileRemovalCannotBeUndoneByLateReports() throws {
        let (core, binding, profile) = context()
        binding.report(EngineDownloadChanged(download: snapshot(profile: UUID())))
        XCTAssertTrue(core.state.downloads.isEmpty)
        let report = snapshot(profile: profile)
        binding.report(EngineDownloadChanged(download: report))
        XCTAssertEqual(core.state.downloads.count, 1)
        try core.send(RemoveProfileDownloads(profileID: profile))
        binding.report(EngineDownloadChanged(download: report))
        XCTAssertTrue(core.state.downloads.isEmpty)
    }

    func testQuitReadsNativeActivityAndDecliningKeepsTheAppOpen() throws {
        let core = CrestCore()
        let host = Prompts()
        core.followPrompts(host)
        let id = UUID()
        try begin(core, id, UUID())
        var allowed: Bool?
        core.prepareToClose(PrepareToQuit(requestID: UUID())) { allowed = $0 }
        XCTAssertNil(allowed)
        let asked = try XCTUnwrap(host.quits.first)
        XCTAssertEqual(asked.liveDownloads, 1)
        try core.send(AnswerQuitWithDownloads(promptID: asked.promptID, quits: false))
        XCTAssertEqual(allowed, false)
        XCTAssertFalse(core.isQuitting)
        try core.send(FinishDownload(downloadID: id, finalByteCount: 10))
        core.prepareToClose(PrepareToQuit(requestID: UUID())) { allowed = $0 }
        XCTAssertEqual(allowed, true)
        XCTAssertEqual(host.quits.count, 1)
    }

    func testTerminalWebKitReportsCannotLeaveAPhantomLiveDownload() throws {
        let (core, binding, profile) = context()
        var report = snapshot(profile: profile)
        binding.report(EngineDownloadChanged(download: report))
        report.state = .failed
        report.interruption = .network
        report.failureDetail = String(repeating: "x", count: DownloadTextField.message.maximumLength + 1)
        binding.report(EngineDownloadChanged(download: report))
        XCTAssertEqual(core.state.downloads.first?.phase, .failed)
        XCTAssertEqual(core.state.downloads.first?.failure, .network)
        XCTAssertNil(core.state.downloads.first?.message)
        report.downloadID = UUID()
        report.state = .finished
        report.received = -1
        binding.report(EngineDownloadChanged(download: report))
        XCTAssertEqual(core.state.downloads.first?.phase, .finished)
        XCTAssertFalse(core.state.downloads.contains { $0.phase.isLive })
    }

    func testDestinationChosenAfterCancellationIsAbandoned() async throws {
        let (core, binding, profile) = context()
        var continuation: CheckedContinuation<any BrowserPlatformDownloadResolution, Never>?
        var abandoned = false
        let prompts = BrowserDownloadPrompts(
            core: core, approve: { _, _ in false },
            resolveDestination: { _, _, _ in
                await withCheckedContinuation { continuation = $0 }
            })
        let report = snapshot(profile: profile)
        binding.report(EngineDownloadChanged(download: report))
        binding.report(
            EngineDownloadDestinationRequested(
                promptID: UUID(), download: report, suggestedFilename: "report.pdf", forcesPrompt: true,
                facts: DownloadRiskFacts(
                    suggestedFilename: "report.pdf", sanitizedFilename: "report.pdf", mimeType: nil,
                    extensionRunsCode: false, mimeTypeRunsCode: false, typesRelated: nil),
                userInitiated: true, sourceHost: nil))
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while continuation == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        let waiting = try XCTUnwrap(continuation)
        try core.send(CancelDownload(downloadID: try XCTUnwrap(core.state.downloads.first).id, message: "Canceled."))
        waiting.resume(returning: DiscardedResolution(discard: { abandoned = true }))
        while !abandoned, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(abandoned)
        XCTAssertTrue(prompts.downloadFolders.isEmpty)
    }

    private func begin(_ core: CrestCore, _ id: UUID, _ profile: UUID, at: Date = .now) throws {
        try core.send(
            BeginDownload(
                downloadID: id, profileID: profile, filename: "report.pdf", createdAt: at, isAcknowledged: false))
    }

    private func context() -> (CrestCore, WebKitEngineBinding, UUID) {
        let profile = UUID()
        let core = CrestCore.hostingPages()
        retainedStores.append(
            BrowserStore(
                seed: SessionState.Seed(spaces: [
                    SpaceState.Seed(id: UUID(), profileID: profile, name: "Work", folders: [], tabs: [])
                ]), core: core))
        return (core, core.engines.webKit!, profile)
    }

    private func snapshot(profile: UUID) -> EngineDownload {
        EngineDownload(
            downloadID: UUID(), profileID: profile, sourcePageID: nil, filename: "report.pdf", path: nil,
            received: 0, total: 100, startedAt: .now, restored: false, paused: false, state: .preparing,
            warning: nil, interruption: nil, failureDetail: nil, approvalToken: "", canPause: false, canResume: false)
    }

    private func destination(_ report: EngineDownload) -> EngineDownloadDestinationRequested {
        EngineDownloadDestinationRequested(
            promptID: UUID(), download: report, suggestedFilename: "invoice.pdf", forcesPrompt: false,
            facts: DownloadRiskFacts(
                suggestedFilename: "invoice\u{202E}.pdf", sanitizedFilename: "invoice.pdf", mimeType: "application/pdf",
                extensionRunsCode: false, mimeTypeRunsCode: false, typesRelated: true),
            userInitiated: true, sourceHost: "example.com")
    }

    private final class Prompts: CorePromptHost {
        var approvals: [DownloadApprovalAsked] = []
        var destinations: [DownloadDestinationAsked] = []
        var quits: [QuitWithDownloadsAsked] = []
        var dismissed: [UUID] = []
        func ask(_ asked: ScriptDialogAsked) {}
        func ask(_ asked: AuthenticationAsked) {}
        func ask(_ asked: PermissionAsked) {}
        func ask(_ asked: ExtensionInstallAsked) {}
        func ask(_ asked: DownloadApprovalAsked) { approvals.append(asked) }
        func ask(_ asked: DownloadDestinationAsked) { destinations.append(asked) }
        func ask(_ asked: QuitWithDownloadsAsked) { quits.append(asked) }
        func dismiss(_ settled: PromptSettled) { dismissed.append(settled.promptID) }
    }

    private struct DiscardedResolution: BrowserPlatformDownloadResolution {
        let discard: @MainActor @Sendable () -> Void
        func abandon() { Task { @MainActor in discard() } }
        @MainActor func answer(_ asked: DownloadDestinationAsked, for prompts: BrowserDownloadPrompts) {
            XCTFail("A canceled download cannot take a later destination")
        }
        @MainActor func save(_ data: Data, as itemID: UUID, from originatingURL: URL, in center: BrowserDownloadCenter)
        {
            XCTFail("A canceled download cannot save data")
        }
    }
}
