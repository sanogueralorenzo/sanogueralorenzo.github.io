import Foundation

protocol DownloadIntent: Sendable {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID]
}

protocol DownloadQuery: Sendable {
    associatedtype Answer: Sendable
    func answer() throws(DownloadLedgerError) -> Answer
}

struct PauseDownload: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
}

struct RemoveProfileDownloads: DownloadIntent, Equatable, Sendable {
    let profileID: UUID
}

struct ResumeDownload: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
}

struct FailDownload: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
    let reason: DownloadFailure?
    let message: String?
}

struct RestartDownload: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
}

struct AnswerDownloadDestination: DownloadIntent, Equatable, Sendable {
    let promptID: UUID
    let path: String?
}

struct BeginDownload: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
    let profileID: UUID
    let filename: String
    let createdAt: Date
    let isAcknowledged: Bool
}

struct ExpireDownloads: DownloadIntent, Equatable, Sendable {
    let now: Date
    let retentions: [DownloadRetention]
}

struct AnswerDownloadApproval: DownloadIntent, Equatable, Sendable {
    let promptID: UUID
    let approved: Bool
}

struct AcknowledgeDownloads: DownloadIntent, Equatable, Sendable {
    let profileID: UUID
}

struct RecordDownloadTransfer: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
    let telemetry: DownloadTelemetry
    let progress: Double
}

struct AwaitDownloadApproval: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
}

struct AssessDownloadRisk: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
    let assessment: DownloadRiskAssessment
}

struct RemoveDownload: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
}

struct FinishDownload: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
    let finalByteCount: Int64?
}

struct CancelDownload: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
    let message: String
}

struct BlockAutomaticDownload: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
}

struct SetDownloadDestination: DownloadIntent, Equatable, Sendable {
    let downloadID: UUID
    let destination: String
    let filename: String
}

struct DownloadProgress: DownloadQuery, Equatable, Sendable {
    typealias Answer = DownloadProgressReading

    let estimator: DownloadTransferEstimator?
    let completedUnitCount: Int64
    let totalUnitCount: Int64
    let fractionCompleted: Double
    let isPaused: Bool
    let uptime: Double
}

struct DownloadRisk: DownloadQuery, Equatable, Sendable {
    typealias Answer = DownloadRiskVerdict

    let facts: DownloadRiskFacts
    let isUserInitiated: Bool
}

extension BeginDownload {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        try store.begin(self)
    }
}

extension SetDownloadDestination {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        try store.destination(self)
    }
}

extension RecordDownloadTransfer {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        try store.transfer(self)
    }
}

extension AssessDownloadRisk {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        try store.assess(self)
    }
}

extension AwaitDownloadApproval {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        store.awaitApproval(downloadID)
    }
}

extension FinishDownload {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        try store.finish(self)
    }
}

extension CancelDownload {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        try store.cancel(self)
    }
}

extension FailDownload {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        try store.fail(self)
    }
}

extension BlockAutomaticDownload {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        store.block(downloadID)
    }
}

extension RestartDownload {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        store.restart(downloadID)
    }
}

extension AcknowledgeDownloads {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        store.acknowledge(profileID)
    }
}

extension RemoveDownload {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        store.remove(downloadID)
    }
}

extension RemoveProfileDownloads {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        store.removeProfile(profileID)
    }
}

extension ExpireDownloads {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        try store.expire(self)
    }
}

extension PauseDownload {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        store.pause(downloadID)
    }
}

extension ResumeDownload {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        store.resume(downloadID)
    }
}

extension AnswerDownloadApproval {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        try store.answer(self)
    }
}

extension AnswerDownloadDestination {
    @MainActor func apply(to store: BrowserNativeDownloads) throws(DownloadLedgerError) -> [UUID] {
        try store.answer(self)
    }
}
