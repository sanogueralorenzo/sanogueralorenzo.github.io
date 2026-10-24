import Foundation

extension EraseProfileData {
    /// Erases every store WebKit keeps for the profile. One that keeps
    /// nothing on disk goes with its store in memory, which no page it builds
    /// uses again.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        binding.memoryStores[profileID] = nil
        guard !ephemeral else {
            binding.report(DataErased(erasureID: erasureID, erased: true))
            return
        }
        let stores = binding.profileStores
        Task { [weak binding] in
            let erased: Bool
            do {
                try await stores.removeProfile(BrowsingProfile(id: profileID), ephemeral: ephemeral)
                erased = true
            } catch {
                erased = false
            }
            binding?.report(DataErased(erasureID: erasureID, erased: erased))
        }
    }
}
