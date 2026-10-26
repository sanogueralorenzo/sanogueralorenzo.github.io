import Foundation

/// A server's request for a user name and password, waiting for the core's
/// answer.
struct WebKitPendingAuthentication: WebKitPendingPrompt {
    // MARK: - Variables

    let pageID: UUID
    let answer: @MainActor (AuthenticationCredential?) -> Void

    // MARK: - Actions - Answers

    @MainActor func decline() {
        answer(nil)
    }

    func declining(_ promptID: UUID) -> any PromptIntent {
        AnswerAuthentication(promptID: promptID, credential: nil)
    }
}
