import Foundation

struct DownloadProgressReading: Equatable, Sendable {
    let estimator: DownloadTransferEstimator
    let telemetry: DownloadTelemetry
    let progress: Double
}

struct DownloadRetention: Equatable, Sendable {
    var profileID: UUID
    var lifetime: TimeInterval?
}

struct DownloadRiskAssessment: Equatable, Sendable {
    var sanitizedFilename: String
    var reasons: [DownloadRiskReason]
}

struct DownloadRiskFacts: Equatable, Sendable {
    static let maximumSuggestedFilenameLength: Int = 4096

    var suggestedFilename: String
    var sanitizedFilename: String
    var mimeType: String?
    var extensionRunsCode: Bool
    var mimeTypeRunsCode: Bool
    var typesRelated: Bool?
}

struct DownloadRiskVerdict: Equatable, Sendable {
    let assessment: DownloadRiskAssessment
    let requiresConfirmation: Bool
}

struct DownloadState: Equatable, Sendable, Identifiable {
    let id: UUID
    let profileID: UUID
    let createdAt: Date
    var filename: String
    var destination: String?
    var progress: Double
    var telemetry: DownloadTelemetry
    var phase: DownloadPhase
    var failure: DownloadFailure?
    var message: String?
    var risk: DownloadRiskAssessment?
    var isAcknowledged: Bool
    var canPause: Bool
    var canResume: Bool
}

struct DownloadTelemetry: Equatable, Sendable {
    static let empty = DownloadTelemetry(
        bytesReceived: 0,
        totalBytes: nil,
        bytesPerSecond: nil,
        estimatedTimeRemaining: nil,
        isPaused: false
    )

    var bytesReceived: Int64
    var totalBytes: Int64?
    var bytesPerSecond: Double?
    var estimatedTimeRemaining: Double?
    var isPaused: Bool
}

struct DownloadTransferEstimator: Equatable, Sendable {
    static let minimumRateInterval: Double = 0.15
    static let smoothingWeight: Double = 0.25
    static let minimumUsefulEstimate: Double = 0.5
    static let maximumUsefulEstimate: Double = 604800
    static let initial = DownloadTransferEstimator(
        publishedBytes: 0,
        knownTotalBytes: nil,
        totalIsUnreliable: false,
        measurementBytes: nil,
        measurementUptime: nil,
        smoothedBytesPerSecond: nil
    )

    var publishedBytes: Int64
    var knownTotalBytes: Int64?
    var totalIsUnreliable: Bool
    var measurementBytes: Int64?
    var measurementUptime: Double?
    var smoothedBytesPerSecond: Double?
}

enum DownloadFailure: String, CaseIterable, Sendable {
    case interrupted = "interrupted"
    case network = "network"
    case server = "server"
    case noSpace = "noSpace"
    case fileAccess = "fileAccess"
    case folderUnavailable = "folderUnavailable"
    case blockedUnsafe = "blockedUnsafe"
    case blockedInsecure = "blockedInsecure"
    case blockedByPolicy = "blockedByPolicy"

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var message: LocalizedStringResource {
        switch self {
        case .interrupted: LocalizedStringResource("The download was interrupted.")
        case .network: LocalizedStringResource("The download stopped because of a network problem.")
        case .server: LocalizedStringResource("The server couldn’t provide the file.")
        case .noSpace: LocalizedStringResource("There isn’t enough disk space to save the file.")
        case .fileAccess: LocalizedStringResource("The file couldn’t be saved in its folder.")
        case .folderUnavailable: LocalizedStringResource("The Downloads folder is unavailable.")
        case .blockedUnsafe: LocalizedStringResource("This download was blocked because it could harm your computer.")
        case .blockedInsecure:
            LocalizedStringResource("This download was blocked because it came over an insecure connection.")
        case .blockedByPolicy: LocalizedStringResource("This download was blocked by a safety or organization policy.")
        }
    }
}

enum DownloadPhase: String, CaseIterable, Sendable {
    case preparing = "preparing"
    case awaitingApproval = "awaitingApproval"
    case downloading = "downloading"
    case finished = "finished"
    case blockedAutomaticDownload = "blockedAutomaticDownload"
    case canceled = "canceled"
    case failed = "failed"

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var title: LocalizedStringResource? {
        switch self {
        case .preparing: LocalizedStringResource("Preparing…")
        case .awaitingApproval: LocalizedStringResource("Waiting for approval…")
        case .downloading: LocalizedStringResource("Downloading…")
        case .finished: LocalizedStringResource("Completed", comment: "Status of a download whose file is saved.")
        case .blockedAutomaticDownload:
            LocalizedStringResource(
                "Automatic download blocked. Use Allow Download to retry, or change Automatic Downloads in this site’s permissions."
            )
        case .canceled: nil
        case .failed: nil
        }
    }

    var symbol: String? {
        switch self {
        case .preparing: nil
        case .awaitingApproval: "exclamationmark.shield.fill"
        case .downloading: nil
        case .finished: nil
        case .blockedAutomaticDownload: "arrow.down.circle.fill"
        case .canceled: "xmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var primaryAction: DownloadRowAction {
        switch self {
        case .preparing: DownloadRowAction.cancel
        case .awaitingApproval: DownloadRowAction.cancel
        case .downloading: DownloadRowAction.cancel
        case .finished: DownloadRowAction.open
        case .blockedAutomaticDownload: DownloadRowAction.retry
        case .canceled: DownloadRowAction.remove
        case .failed: DownloadRowAction.remove
        }
    }

    var isLive: Bool {
        switch self {
        case .preparing: true
        case .awaitingApproval: true
        case .downloading: true
        case .finished: false
        case .blockedAutomaticDownload: false
        case .canceled: false
        case .failed: false
        }
    }

    var isTransferring: Bool {
        switch self {
        case .preparing: false
        case .awaitingApproval: false
        case .downloading: true
        case .finished: false
        case .blockedAutomaticDownload: false
        case .canceled: false
        case .failed: false
        }
    }

    var isComplete: Bool {
        switch self {
        case .preparing: false
        case .awaitingApproval: false
        case .downloading: false
        case .finished: true
        case .blockedAutomaticDownload: false
        case .canceled: false
        case .failed: false
        }
    }

    var needsAttention: Bool {
        switch self {
        case .preparing: false
        case .awaitingApproval: false
        case .downloading: false
        case .finished: false
        case .blockedAutomaticDownload: true
        case .canceled: false
        case .failed: true
        }
    }

    var awaitsDecision: Bool {
        switch self {
        case .preparing: false
        case .awaitingApproval: true
        case .downloading: false
        case .finished: false
        case .blockedAutomaticDownload: true
        case .canceled: false
        case .failed: false
        }
    }

    var canRetry: Bool {
        switch self {
        case .preparing: false
        case .awaitingApproval: false
        case .downloading: false
        case .finished: false
        case .blockedAutomaticDownload: true
        case .canceled: false
        case .failed: false
        }
    }

    var allowsResume: Bool {
        switch self {
        case .preparing: false
        case .awaitingApproval: false
        case .downloading: true
        case .finished: false
        case .blockedAutomaticDownload: false
        case .canceled: false
        case .failed: true
        }
    }

    var canFail: Bool {
        switch self {
        case .preparing: true
        case .awaitingApproval: true
        case .downloading: true
        case .finished: false
        case .blockedAutomaticDownload: true
        case .canceled: false
        case .failed: false
        }
    }
}

enum DownloadRiskReason: String, CaseIterable, Sendable {
    case executableOrInstaller = "executableOrInstaller"
    case deceptiveFilename = "deceptiveFilename"
    case dangerousTypeMismatch = "dangerousTypeMismatch"

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var confirmsUserInitiated: Bool {
        switch self {
        case .executableOrInstaller: false
        case .deceptiveFilename: true
        case .dangerousTypeMismatch: true
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .executableOrInstaller: LocalizedStringResource("This file type can install or run software.")
        case .deceptiveFilename:
            LocalizedStringResource(
                "The original filename used invisible or direction-changing characters that can disguise its real extension."
            )
        case .dangerousTypeMismatch:
            LocalizedStringResource(
                "The server-reported file type does not match the filename and one of those types can run software.")
        }
    }
}

enum DownloadRowAction: String, CaseIterable, Sendable {
    case retry = "retry"
    case cancel = "cancel"
    case open = "open"
    case remove = "remove"
    case pause = "pause"
    case resume = "resume"

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }
    typealias Kind = DownloadRowAction
    var kind: Kind { self }

    var title: LocalizedStringResource {
        switch self {
        case .retry: LocalizedStringResource("Allow Download")
        case .cancel: LocalizedStringResource("Cancel Download")
        case .open: LocalizedStringResource("Download Actions")
        case .remove: LocalizedStringResource("Remove Download")
        case .pause: LocalizedStringResource("Pause Download")
        case .resume: LocalizedStringResource("Resume Download")
        }
    }

    var symbol: String {
        switch self {
        case .retry: "arrow.clockwise"
        case .cancel: "xmark"
        case .open: "square.and.arrow.up"
        case .remove: "trash"
        case .pause: "pause"
        case .resume: "play"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .retry: false
        case .cancel: false
        case .open: false
        case .remove: true
        case .pause: false
        case .resume: false
        }
    }
}

enum DownloadTextField: String, CaseIterable, Sendable {
    case filename = "filename"
    case destination = "destination"
    case message = "message"
    case mimeType = "mimeType"

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var maximumLength: Int {
        switch self {
        case .filename: 1024
        case .destination: 8192
        case .message: 2048
        case .mimeType: 255
        }
    }
}

enum DownloadWarning: String, CaseIterable, Sendable {
    case insecureConnection = "insecureConnection"
    case dangerousFile = "dangerousFile"
    case uncommonContent = "uncommonContent"
    case potentiallyUnwanted = "potentiallyUnwanted"
    case insecureBlocked = "insecureBlocked"
    case policyBlocked = "policyBlocked"

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }

    var engineWarning: EngineDownloadWarning {
        switch self {
        case .insecureConnection: .insecureConnection
        case .dangerousFile: .dangerousFile
        case .uncommonContent: .uncommonContent
        case .potentiallyUnwanted: .potentiallyUnwanted
        case .insecureBlocked: .insecureBlocked
        case .policyBlocked: .policyBlocked
        }
    }

    var approvalMessage: LocalizedStringResource {
        switch self {
        case .insecureConnection:
            LocalizedStringResource(
                "This file was transferred over an insecure connection and could have been changed by someone else. Keep it only if you trust its source."
            )
        case .dangerousFile:
            LocalizedStringResource(
                "This type of file can change your computer. Keep it only if you trust its source.")
        case .uncommonContent:
            LocalizedStringResource(
                "This file is not commonly downloaded. The engine could not confirm that it is safe.")
        case .potentiallyUnwanted:
            LocalizedStringResource(
                "This file may change your browser or computer settings without your permission.")
        case .insecureBlocked: LocalizedStringResource("The engine blocked this insecure download.")
        case .policyBlocked:
            LocalizedStringResource(
                "The engine blocked this download because of its safety or organization policy verdict.")
        }
    }

    var failure: DownloadFailure {
        switch self {
        case .insecureConnection: DownloadFailure.blockedInsecure
        case .dangerousFile: DownloadFailure.blockedUnsafe
        case .uncommonContent: DownloadFailure.blockedUnsafe
        case .potentiallyUnwanted: DownloadFailure.blockedUnsafe
        case .insecureBlocked: DownloadFailure.blockedInsecure
        case .policyBlocked: DownloadFailure.blockedByPolicy
        }
    }

    var coveredBy: [DownloadRiskReason] {
        switch self {
        case .insecureConnection: []
        case .dangerousFile: [DownloadRiskReason.executableOrInstaller, DownloadRiskReason.dangerousTypeMismatch]
        case .uncommonContent: []
        case .potentiallyUnwanted: []
        case .insecureBlocked: []
        case .policyBlocked: []
        }
    }
}

struct DownloadApprovalAsked: Equatable, Sendable {
    let promptID: UUID
    let downloadID: UUID
    let spaceID: UUID?
    let filename: String
    let reasons: [DownloadRiskReason]
    let warning: DownloadWarning?
    let sourceHost: String?
}

struct DownloadDestinationAsked: Equatable, Sendable {
    let promptID: UUID
    let downloadID: UUID
    let spaceID: UUID
    let suggestedFilename: String
    let forcesPrompt: Bool
}

struct DownloadStarted: Equatable, Sendable {
    let downloadID: UUID
    let pageID: UUID
}

struct EngineDownload: Equatable, Sendable {
    var downloadID: UUID
    var profileID: UUID
    var sourcePageID: UUID?
    var filename: String
    var path: String?
    var received: Int64
    var total: Int64
    var startedAt: Date
    var restored: Bool
    var paused: Bool
    var state: EngineDownloadState
    var warning: EngineDownloadWarning?
    var interruption: EngineDownloadInterruption?
    var failureDetail: String?
    var approvalToken: String
    var canPause: Bool
    var canResume: Bool
}

enum EngineDownloadInterruption: Int, CaseIterable, Sendable {
    case network = 0
    case server = 1
    case noSpace = 2
    case fileAccess = 3
    case other = 4
}

enum EngineDownloadState: Int, CaseIterable, Sendable {
    case preparing = 0
    case downloading = 1
    case awaitingApproval = 2
    case finished = 3
    case canceled = 4
    case failed = 5
    case blocked = 6
}

enum EngineDownloadWarning: Int, CaseIterable, Sendable {
    case insecureConnection = 0
    case dangerousFile = 1
    case uncommonContent = 2
    case potentiallyUnwanted = 3
    case insecureBlocked = 4
    case policyBlocked = 5
}

struct EngineDownloadChanged: Equatable, Sendable {
    let download: EngineDownload
}

struct EngineDownloadDestinationRequested: Equatable, Sendable {
    let promptID: UUID
    let download: EngineDownload
    let suggestedFilename: String
    let forcesPrompt: Bool
    let facts: DownloadRiskFacts
    let userInitiated: Bool
    let sourceHost: String?
}

enum AutomaticDownloadAction: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case allow = "allow"
    case deny = "deny"
    case requestPermission = "requestPermission"

    var name: String { rawValue }
    static let all = allCases
    static func named(_ name: String?) -> Self? { name.flatMap(Self.init(rawValue:)) }
    typealias Kind = AutomaticDownloadAction
    var kind: Kind { self }
}

struct AutomaticDownloadCheck: Equatable, Sendable {

    let userInitiated: Bool
    let userApprovedRetry: Bool
    let savedDecision: SitePermissionDecision
    let hasAllowedAutomaticDownload: Bool
}

struct AutomaticDownloadVerdict: Equatable, Sendable {
    let action: AutomaticDownloadAction
    let hasAllowedAutomaticDownload: Bool
}
