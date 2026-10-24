import Foundation

/// Shows the person a script dialog a page's document opened, one method per
/// kind of dialog, and hands `reply` whether they accepted it and the text
/// they entered. Each dialog closes once `dismissal` says it no longer waits.
@MainActor
protocol BrowserScriptDialogPresenting {
    typealias Reply = @MainActor @Sendable (_ accepted: Bool, _ text: String?) -> Void

    func presentAlert(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    )
    func presentConfirm(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    )
    func presentPrompt(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    )
    func presentBeforeUnload(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    )
}
