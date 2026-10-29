import Foundation

struct ImportExtensionInstall: Equatable, Sendable {
    var extensionID: String
    var name: String
    var iconPath: String?
    var spaceIDs: [UUID]
}

struct ImportFailure: Equatable, Sendable {
    var reason: ImportFailureReason
    var source: ImportSource?
    var detail: String?
}

struct ImportFlowState: Equatable, Sendable {
    var workspaceID: UUID
    var step: ImportStep
    var phase: ImportPhase
    var offered: [ImportSource]
    var selected: [ImportSource]
    var queue: ImportQueue?
    var source: ImportSource?
    var review: ImportReview?
    var failure: ImportFailure?
    var summary: ImportSummary?
}

struct ImportSummary: Equatable, Sendable {
    var tabCount: Int
    var spaceCount: Int
}
