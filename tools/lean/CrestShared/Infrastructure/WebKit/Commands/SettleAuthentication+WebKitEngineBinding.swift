import Foundation

extension SettleAuthentication {
    @MainActor func perform(on binding: WebKitEngineBinding) {
        guard let prompt = binding.prompts.removeValue(forKey: promptID) as? WebKitPendingAuthentication else {
            return
        }
        prompt.answer(credential)
    }
}
