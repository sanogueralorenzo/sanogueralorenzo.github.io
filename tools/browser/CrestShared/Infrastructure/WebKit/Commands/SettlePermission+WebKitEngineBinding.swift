import Foundation

extension SettlePermission {
    @MainActor func perform(on binding: WebKitEngineBinding) {
        guard let prompt = binding.prompts.removeValue(forKey: promptID) as? WebKitPendingPermission else { return }
        prompt.answer(grants)
    }
}
