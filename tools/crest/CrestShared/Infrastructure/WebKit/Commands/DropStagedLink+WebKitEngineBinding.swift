import Foundation

extension DropStagedLink {
    @MainActor func perform(on binding: WebKitEngineBinding) {
        binding.stagedLinks[stagedLinkID] = nil
    }
}
