import Foundation

struct PrepareToClosePages: CloseRequest, Equatable, Sendable {
    let requestID: UUID
    let pageIDs: [UUID]
}

struct PrepareToCloseWindows: CloseRequest, Equatable, Sendable {
    let requestID: UUID
    let windowIDs: [UUID]
}

struct PrepareToQuit: CloseRequest, Equatable, Sendable {
    let requestID: UUID
}

struct AnswerQuitWithDownloads: Equatable, Sendable {
    let promptID: UUID
    let quits: Bool
}

struct QuitWithDownloadsAsked: Equatable, Sendable {
    let promptID: UUID
    let requestID: UUID
    let liveDownloads: Int
}

struct PromptSettled: Equatable, Sendable {
    let promptID: UUID
}

struct SpaceDeletionUnderway: Equatable, Sendable {
    let spaceIDs: [UUID]

    var message: LocalizedStringResource {
        LocalizedStringResource("Crest will quit once the Space is deleted.")
    }
}
