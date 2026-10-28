import Foundation

extension EraseProfileData {
    /// Erases every store WebKit keeps for the profile. One that keeps
    /// nothing on disk goes with its store in memory, which no page it builds
    /// uses again.
    @MainActor func perform(on binding: WebKitEngineBinding) {
        binding.invalidateIntegrationSessions(profileID: profileID)
        let stores = binding.profileStores
        let blocking = binding.contentBlocking
        let isEphemeral = ephemeral || binding.keepsProfilesInMemory
        Task { [weak binding] in
            let erased: Bool
            do {
                try await blocking.removeData(profileID: profileID, isEphemeral: isEphemeral)
                binding?.memoryStores[profileID] = nil
                if !ephemeral { try await stores.removeProfile(BrowsingProfile(id: profileID), ephemeral: ephemeral) }
                erased = true
            } catch {
                erased = false
            }
            binding?.report(DataErased(erasureID: erasureID, erased: erased))
        }
    }
}
