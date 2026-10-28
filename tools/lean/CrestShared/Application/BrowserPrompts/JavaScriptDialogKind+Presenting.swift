import Foundation

extension JavaScriptDialogKind {
    /// Shows `question`, a dialog of this kind, on `presenter`.
    @MainActor func present(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal,
        on presenter: some BrowserScriptDialogPresenting,
        reply: @escaping BrowserScriptDialogPresenting.Reply
    ) {
        switch self {
        case .alert: presenter.presentAlert(question, request: request, dismissal: dismissal, reply: reply)
        case .confirm: presenter.presentConfirm(question, request: request, dismissal: dismissal, reply: reply)
        case .prompt: presenter.presentPrompt(question, request: request, dismissal: dismissal, reply: reply)
        case .beforeUnload:
            presenter.presentBeforeUnload(question, request: request, dismissal: dismissal, reply: reply)
        }
    }
}
