import Foundation

/// A script dialog a page opened, waiting for the core's answer.
struct WebKitPendingScriptDialog: WebKitPendingPrompt {
    // MARK: - Variables

    let pageID: UUID
    let answer: @MainActor (Bool, String?) -> Void

    // MARK: - Actions - Answers

    @MainActor func decline() {
        answer(false, nil)
    }

    func declining(_ promptID: UUID) -> any PromptIntent {
        AnswerScriptDialog(promptID: promptID, accepted: false, text: nil)
    }
}
