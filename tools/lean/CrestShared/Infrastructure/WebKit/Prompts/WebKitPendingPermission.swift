import Foundation

/// A site's request for a capability, waiting for the core's answer.
struct WebKitPendingPermission: WebKitPendingPrompt {
    // MARK: - Variables

    let pageID: UUID
    let answer: @MainActor (Bool) -> Void

    // MARK: - Actions - Answers

    @MainActor func decline() {
        answer(false)
    }

    func declining(_ promptID: UUID) -> any PromptIntent {
        AnswerPermission(promptID: promptID, grants: false, remembers: false)
    }
}
