import Foundation

protocol PromptIntent: Sendable {
    @MainActor func apply(to prompts: NativeBrowserPrompts) throws(NativeBrowserPrompts.Failure)
}
protocol PromptEvent: Sendable {
    @MainActor func apply(to prompts: NativeBrowserPrompts, from binding: WebKitEngineBinding)
}

extension AnswerAuthentication {
    @MainActor func apply(to prompts: NativeBrowserPrompts) throws(NativeBrowserPrompts.Failure) {
        try prompts.answer(self)
    }
}
extension AnswerPermission {
    @MainActor func apply(to prompts: NativeBrowserPrompts) throws(NativeBrowserPrompts.Failure) {
        try prompts.answer(self)
    }
}
extension AnswerScriptDialog {
    @MainActor func apply(to prompts: NativeBrowserPrompts) throws(NativeBrowserPrompts.Failure) {
        try prompts.answer(self)
    }
}
extension AnswerExtensionInstall {
    @MainActor func apply(to prompts: NativeBrowserPrompts) throws(NativeBrowserPrompts.Failure) {
        try prompts.answer(self)
    }
}
extension AuthenticationChallenged {
    @MainActor func apply(to prompts: NativeBrowserPrompts, from binding: WebKitEngineBinding) {
        prompts.raise(self, from: binding)
    }
}
extension PermissionRequested {
    @MainActor func apply(to prompts: NativeBrowserPrompts, from binding: WebKitEngineBinding) {
        prompts.raise(self, from: binding)
    }
}
extension ScriptDialogOpened {
    @MainActor func apply(to prompts: NativeBrowserPrompts, from binding: WebKitEngineBinding) {
        prompts.raise(self, from: binding)
    }
}
extension ExtensionInstallRequested {
    @MainActor func apply(to prompts: NativeBrowserPrompts, from binding: WebKitEngineBinding) {
        prompts.raise(self, from: binding)
    }
}
extension PromptWithdrawn {
    @MainActor func apply(to prompts: NativeBrowserPrompts, from binding: WebKitEngineBinding) {
        prompts.withdraw(promptID, from: binding)
    }
}
