import Foundation

extension SettleScriptDialog {
    @MainActor func perform(on binding: WebKitEngineBinding) {
        guard let prompt = binding.prompts.removeValue(forKey: promptID) as? WebKitPendingScriptDialog else { return }
        prompt.answer(accepted, text)
    }
}
